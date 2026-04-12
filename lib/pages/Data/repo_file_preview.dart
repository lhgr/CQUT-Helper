import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:cqut_helper/manager/preview_cache_manager.dart';
import 'package:cqut_helper/manager/resumable_downloader.dart';
import 'package:cqut_helper/model/github_item.dart';
import 'package:cqut_helper/utils/github_proxy.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _PreviewKind { image, markdown, pdf, video, audio, office, unsupported }

class RepoFilePreviewPage extends StatefulWidget {
  final GithubItem item;

  const RepoFilePreviewPage({super.key, required this.item});

  @override
  State<RepoFilePreviewPage> createState() => _RepoFilePreviewPageState();
}

class _RepoFilePreviewPageState extends State<RepoFilePreviewPage> {
  final Dio _dio = Dio();
  static const int _largePdfMaxCachedPages = 6;
  static const int _pdfSegmentBytes = 1024 * 1024;
  static const int _pdfSegmentRetryTimes = 3;

  late final _PreviewKind _kind;
  late final String _ext;
  Future<String>? _textFuture;
  Future<_PdfPreviewBundle>? _pdfFuture;
  Future<_VideoPreviewBundle>? _videoFuture;
  _AudioPreviewBundle? _audioBundle;
  WebViewController? _webViewController;
  final Map<int, Uint8List> _pdfPageCache = <int, Uint8List>{};
  final Queue<int> _pdfPageLru = Queue<int>();
  final Map<int, Object> _pdfPageErrors = <int, Object>{};
  final Map<int, Future<Uint8List>> _pdfPageTasks = <int, Future<Uint8List>>{};
  PageController? _largePdfPageController;
  int _largePdfCurrentPage = 1;

  @override
  void initState() {
    super.initState();
    _ext = _fileExt(widget.item.name);
    _kind = _decideKind(_ext);
    unawaited(PreviewCacheManager.cleanupIfNeeded());

    if (_kind == _PreviewKind.markdown) {
      _textFuture = _loadText();
    } else if (_kind == _PreviewKind.pdf) {
      _pdfFuture = _loadPdf();
    } else if (_kind == _PreviewKind.video) {
      _videoFuture = _loadVideo();
    } else if (_kind == _PreviewKind.audio) {
      _initAudio();
    } else if (_kind == _PreviewKind.office) {
      _initOfficeWebView();
    }
  }

  @override
  void dispose() {
    _webViewController = null;
    _audioBundle?.dispose();
    _videoFuture?.then((b) => b.dispose());
    _pdfFuture?.then((b) => b.dispose());
    _largePdfPageController?.dispose();
    super.dispose();
  }

  String _fileExt(String name) {
    final idx = name.lastIndexOf('.');
    if (idx <= 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  _PreviewKind _decideKind(String ext) {
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return _PreviewKind.image;
      case 'md':
      case 'markdown':
        return _PreviewKind.markdown;
      case 'pdf':
        return _PreviewKind.pdf;
      case 'mp4':
      case 'mov':
      case 'mkv':
      case 'webm':
        return _PreviewKind.video;
      case 'mp3':
      case 'm4a':
      case 'aac':
      case 'wav':
      case 'flac':
        return _PreviewKind.audio;
      case 'doc':
      case 'docx':
      case 'ppt':
      case 'pptx':
        return _PreviewKind.office;
      default:
        return _PreviewKind.unsupported;
    }
  }

  Uri? _rawUri() {
    final url = widget.item.downloadUrl;
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  Future<void> _openGithubOriginal() async {
    final uri = Uri.tryParse(widget.item.htmlUrl);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无效链接: ${widget.item.htmlUrl}')));
      }
      return;
    }
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: ${widget.item.htmlUrl}')));
    }
  }

  Future<String> _loadText() async {
    final raw = _rawUri();
    if (raw == null) throw Exception('该文件没有可用的下载地址');
    final resp = await GithubProxy.getWithFallback<String>(
      _dio,
      raw,
      options: Options(responseType: ResponseType.plain),
    );
    final data = resp.data;
    if (data == null) throw Exception('内容为空');
    return data;
  }

  Future<_PdfPreviewBundle> _loadPdf() async {
    final raw = _rawUri();
    if (raw == null) throw Exception('该文件没有可用的下载地址');
    _resetLargePdfCache();
    final file = await _ensureLocalFile(raw);
    final document = await PdfDocument.openFile(file.path);
    final pagesCount = document.pagesCount;
    return _PdfPreviewBundle(
      pinchController: null,
      document: document,
      isPaged: true,
      pagesCount: pagesCount,
    );
  }

  Future<File> _ensureLocalFile(Uri raw) async {
    final dir = await PreviewCacheManager.resolveDir();

    final key = sha1.convert(utf8.encode(raw.toString())).toString();
    final ext = _ext.isEmpty ? '' : '.$_ext';
    final path = '${dir.path}/$key$ext';
    final file = File(path);
    if (await file.exists()) {
      final len = await file.length();
      if (len > 0) {
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return file;
      }
    }

    final downloader = ResumableDownloader();
    int received = 0;
    int total = -1;
    if (mounted) {
      setState(() {});
    }
    await downloader.downloadFileResumable(
      raw,
      file.path,
      segmented: true,
      segmentBytes: _pdfSegmentBytes,
      retryTimesPerSegment: _pdfSegmentRetryTimes,
      onReceiveProgress: (r, t) {
        received = r;
        total = t;
        if (!mounted) return;
        setState(() {
          if (total > 0) {
            final v = received / total;
            _downloadProgress = v.clamp(0.0, 1.0);
          } else {
            _downloadProgress = null;
          }
        });
      },
    );
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {}
    if (mounted) {
      setState(() {
        _downloadProgress = 1.0;
      });
    }
    return file;
  }

  double? _downloadProgress;

  void _resetLargePdfCache() {
    _pdfPageCache.clear();
    _pdfPageLru.clear();
    _pdfPageErrors.clear();
    _pdfPageTasks.clear();
    _largePdfCurrentPage = 1;
    _largePdfPageController?.dispose();
    _largePdfPageController = null;
  }

  void _retryPdfLoad() {
    if (_kind != _PreviewKind.pdf) return;
    setState(() {
      _downloadProgress = null;
      _pdfFuture = _loadPdf();
    });
  }

  Future<void> _showPdfPageJumpDialog(int totalPages) async {
    if (totalPages <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前文档页数异常，暂不可跳转')));
      return;
    }
    var inputValue = _largePdfCurrentPage.toString();
    final target = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('跳转页码'),
          content: TextFormField(
            initialValue: inputValue,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '请输入 1 - $totalPages'),
            onChanged: (value) {
              inputValue = value;
            },
            onFieldSubmitted: (value) {
              final page = int.tryParse(value.trim());
              Navigator.of(context).pop(page);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final page = int.tryParse(inputValue.trim());
                Navigator.of(context).pop(page);
              },
              child: const Text('跳转'),
            ),
          ],
        );
      },
    );
    if (!mounted || target == null) return;
    final page = target;
    if (page < 1 || page > totalPages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('页码范围应为 1 - $totalPages')));
      return;
    }
    _jumpToPdfPage(page, totalPages);
  }

  void _jumpToPdfPage(int page, int totalPages) {
    if (page < 1 || page > totalPages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('页码范围应为 1 - $totalPages')));
      return;
    }
    final controller = _largePdfPageController;
    if (controller == null || !controller.hasClients) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('页面尚未就绪，请稍后重试')));
      return;
    }
    controller
        .animateToPage(
          page - 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .catchError((_) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('跳转失败，请重试')));
        });
  }

  Future<Uint8List> _ensurePdfPageImage(
    _PdfPreviewBundle bundle,
    int pageNumber, {
    bool highPriority = false,
  }) {
    final cached = _pdfPageCache[pageNumber];
    if (cached != null) return Future<Uint8List>.value(cached);
    final running = _pdfPageTasks[pageNumber];
    if (running != null) return running;
    final document = bundle.document;
    if (document == null) {
      return Future<Uint8List>.error(Exception('文档不可用'));
    }
    _pdfPageErrors.remove(pageNumber);
    final task = () async {
      final page = await document.getPage(pageNumber);
      try {
        final scale = highPriority ? 2.0 : 1.4;
        final width = page.width * scale;
        final height = page.height * scale;
        final image = await page.render(
          width: width,
          height: height,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        final bytes = image?.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw Exception('页面渲染结果为空');
        }
        if (mounted) {
          setState(() {
            _pdfPageCache[pageNumber] = bytes;
            _pdfPageLru.remove(pageNumber);
            _pdfPageLru.addLast(pageNumber);
            while (_pdfPageLru.length > _largePdfMaxCachedPages) {
              final victim = _pdfPageLru.removeFirst();
              if (victim == _largePdfCurrentPage) {
                _pdfPageLru.addLast(victim);
                if (_pdfPageLru.length <= _largePdfMaxCachedPages) break;
                continue;
              }
              _pdfPageCache.remove(victim);
            }
          });
        }
        return bytes;
      } finally {
        await page.close();
      }
    }();
    _pdfPageTasks[pageNumber] = task;
    task
        .then((_) {
          _pdfPageTasks.remove(pageNumber);
        })
        .catchError((error) {
          _pdfPageTasks.remove(pageNumber);
          if (mounted) {
            setState(() {
              _pdfPageErrors[pageNumber] = error;
            });
          }
        });
    return task;
  }

  Future<void> _prefetchAdjacentPdfPages(
    _PdfPreviewBundle bundle,
    int currentPage,
  ) async {
    final pages = bundle.pagesCount;
    final candidates = <int>[
      if (currentPage > 1) currentPage - 1,
      if (currentPage < pages) currentPage + 1,
    ];
    for (final page in candidates) {
      unawaited(
        _ensurePdfPageImage(bundle, page).catchError((_) {
          return Uint8List(0);
        }),
      );
    }
  }

  Future<_VideoPreviewBundle> _loadVideo() async {
    final raw = _rawUri();
    if (raw == null) throw Exception('该文件没有可用的下载地址');
    final candidates = <Uri>[raw];
    if (GithubProxy.isGithubUri(raw) && !GithubProxy.isWorkerUri(raw)) {
      candidates
        ..clear()
        ..add(GithubProxy.proxyUriOf(raw))
        ..add(raw);
    }

    Object? lastError;
    for (final uri in candidates) {
      final controller = VideoPlayerController.networkUrl(uri);
      try {
        await controller.initialize();
        final chewie = ChewieController(
          videoPlayerController: controller,
          autoPlay: false,
          looping: false,
        );
        return _VideoPreviewBundle(video: controller, chewie: chewie);
      } catch (e) {
        lastError = e;
        await controller.dispose();
      }
    }
    throw lastError ?? Exception('视频初始化失败');
  }

  Future<void> _initAudio() async {
    final raw = _rawUri();
    if (raw == null) return;
    final candidates = <Uri>[raw];
    if (GithubProxy.isGithubUri(raw) && !GithubProxy.isWorkerUri(raw)) {
      candidates
        ..clear()
        ..add(GithubProxy.proxyUriOf(raw))
        ..add(raw);
    }

    final player = AudioPlayer();
    player.setReleaseMode(ReleaseMode.stop);

    Object? lastError;
    for (final uri in candidates) {
      try {
        await player.setSourceUrl(uri.toString());
        if (!mounted) {
          await player.dispose();
          return;
        }
        setState(() {
          _audioBundle = _AudioPreviewBundle(player: player, source: uri);
        });
        return;
      } catch (e) {
        lastError = e;
      }
    }

    await player.dispose();
    if (!mounted) return;
    setState(() {
      _audioBundle = _AudioPreviewBundle(
        player: null,
        source: null,
        error: lastError,
      );
    });
  }

  void _initOfficeWebView() {
    final raw = _rawUri();
    if (raw == null) return;
    final src = raw.toString();
    final viewer = Uri.https('view.officeapps.live.com', '/op/view.aspx', {
      'src': src,
    });

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('加载失败：${error.description}')),
            );
          },
        ),
      )
      ..loadRequest(viewer);

    _webViewController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          IconButton(
            onPressed: _openGithubOriginal,
            icon: Icon(Icons.open_in_new),
            tooltip: '在 GitHub 打开',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_kind == _PreviewKind.image) {
      final raw = _rawUri();
      if (raw == null) return _buildUnsupported();
      return InteractiveViewer(
        child: Image.network(
          GithubProxy.proxyUrlOf(raw.toString()),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              Center(child: Text('图片加载失败')),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            final value = progress.expectedTotalBytes == null
                ? null
                : progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!.toDouble();
            return Center(child: CircularProgressIndicator(value: value));
          },
        ),
      );
    }

    if (_kind == _PreviewKind.markdown) {
      final future = _textFuture;
      if (future == null) return _buildUnsupported();
      return FutureBuilder<String>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }
          final data = snapshot.data ?? '';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: data,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              onTapLink: (text, href, title) {
                if (href == null || href.isEmpty) return;
                GithubProxy.launchExternalUrlString(href);
              },
            ),
          );
        },
      );
    }

    if (_kind == _PreviewKind.pdf) {
      final future = _pdfFuture;
      if (future == null) return _buildUnsupported();
      return FutureBuilder<_PdfPreviewBundle>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            final p = _downloadProgress;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(value: p),
                  ),
                  SizedBox(height: 12),
                  Text(
                    p == null
                        ? '正在加载…'
                        : '正在加载 ${(p * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _buildError(
              snapshot.error.toString(),
              onRetry: _retryPdfLoad,
            );
          }
          final bundle = snapshot.data;
          if (bundle == null) {
            return _buildError('加载失败', onRetry: _retryPdfLoad);
          }
          return _buildPagedPdf(bundle);
        },
      );
    }

    if (_kind == _PreviewKind.video) {
      final future = _videoFuture;
      if (future == null) return _buildUnsupported();
      return FutureBuilder<_VideoPreviewBundle>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }
          final bundle = snapshot.data;
          if (bundle == null) return _buildError('加载失败');
          return Center(child: Chewie(controller: bundle.chewie));
        },
      );
    }

    if (_kind == _PreviewKind.audio) {
      final bundle = _audioBundle;
      if (bundle == null) {
        return Center(child: CircularProgressIndicator());
      }
      if (bundle.player == null) {
        return _buildError(bundle.error?.toString() ?? '加载失败');
      }
      return _buildAudio(bundle.player!);
    }

    if (_kind == _PreviewKind.office) {
      final controller = _webViewController;
      if (controller == null) return _buildUnsupported();
      return WebViewWidget(controller: controller);
    }

    return _buildUnsupported();
  }

  Widget _buildAudio(AudioPlayer player) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.audiotrack, size: 56),
          SizedBox(height: 16),
          Text(widget.item.name, textAlign: TextAlign.center),
          SizedBox(height: 24),
          StreamBuilder<PlayerState>(
            stream: player.onPlayerStateChanged,
            builder: (context, snapshot) {
              final state = snapshot.data ?? PlayerState.stopped;
              final playing = state == PlayerState.playing;
              return FilledButton.icon(
                onPressed: () async {
                  if (playing) {
                    await player.pause();
                  } else {
                    await player.resume();
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                label: Text(playing ? '暂停' : '播放'),
              );
            },
          ),
          SizedBox(height: 16),
          StreamBuilder<Duration>(
            stream: player.onDurationChanged,
            builder: (context, durationSnap) {
              final duration = durationSnap.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: player.onPositionChanged,
                builder: (context, posSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final maxMs = duration.inMilliseconds
                      .toDouble()
                      .clamp(0.0, double.infinity)
                      .toDouble();
                  final valueMs = pos.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxMs)
                      .toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: maxMs == 0 ? 0 : valueMs,
                        min: 0,
                        max: maxMs == 0 ? 1 : maxMs,
                        onChanged: (v) async {
                          await player.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmtDuration(pos)),
                          Text(_fmtDuration(duration)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPagedPdf(_PdfPreviewBundle bundle) {
    final document = bundle.document;
    if (document == null) return _buildError('加载失败', onRetry: _retryPdfLoad);
    final pages = bundle.pagesCount;
    _largePdfPageController ??= PageController(
      initialPage: (_largePdfCurrentPage - 1).clamp(0, pages - 1),
    );
    unawaited(
      _ensurePdfPageImage(
        bundle,
        _largePdfCurrentPage,
        highPriority: true,
      ).catchError((_) {
        return Uint8List(0);
      }),
    );
    unawaited(_prefetchAdjacentPdfPages(bundle, _largePdfCurrentPage));
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _largePdfPageController,
            scrollDirection: Axis.vertical,
            itemCount: pages,
            onPageChanged: (index) {
              _largePdfCurrentPage = index + 1;
              if (mounted) {
                setState(() {});
              }
              unawaited(
                _ensurePdfPageImage(
                  bundle,
                  _largePdfCurrentPage,
                  highPriority: true,
                ).catchError((_) {
                  return Uint8List(0);
                }),
              );
              unawaited(
                _prefetchAdjacentPdfPages(bundle, _largePdfCurrentPage),
              );
            },
            itemBuilder: (context, index) {
              final page = index + 1;
              final cached = _pdfPageCache[page];
              if (cached != null && cached.isNotEmpty) {
                return Center(
                  child: Image.memory(
                    cached,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                );
              }
              final pageError = _pdfPageErrors[page];
              if (pageError != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 12),
                        Text('第 $page 页加载失败'),
                        const SizedBox(height: 8),
                        Text(
                          pageError.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _pdfPageErrors.remove(page);
                              _pdfPageTasks.remove(page);
                              _pdfPageCache.remove(page);
                              _pdfPageLru.remove(page);
                            });
                            unawaited(
                              _ensurePdfPageImage(
                                bundle,
                                page,
                                highPriority: true,
                              ).catchError((_) {
                                return Uint8List(0);
                              }),
                            );
                          },
                          child: const Text('重试本页'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return FutureBuilder<Uint8List>(
                future: _ensurePdfPageImage(
                  bundle,
                  page,
                  highPriority: page == _largePdfCurrentPage,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(),
                          ),
                          const SizedBox(height: 10),
                          Text('正在渲染第 $page 页'),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _pdfPageErrors.remove(page);
                            _pdfPageTasks.remove(page);
                          });
                          unawaited(
                            _ensurePdfPageImage(
                              bundle,
                              page,
                              highPriority: true,
                            ).catchError((_) {
                              return Uint8List(0);
                            }),
                          );
                        },
                        child: const Text('重试本页'),
                      ),
                    );
                  }
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    return const Center(child: Text('页面为空'));
                  }
                  return Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_largePdfCurrentPage / $pages',
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showPdfPageJumpDialog(pages),
                  icon: const Icon(Icons.find_in_page_outlined),
                  label: const Text('跳转'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  Widget _buildUnsupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 56),
            SizedBox(height: 12),
            Text('该文件暂不支持预览'),
            SizedBox(height: 16),
            FilledButton(
              onPressed: _openGithubOriginal,
              child: Text('前往 GitHub 查看'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red),
            SizedBox(height: 12),
            Text('加载失败'),
            SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: _openGithubOriginal,
                  child: Text('前往 GitHub 查看'),
                ),
                if (onRetry != null) ...[
                  SizedBox(width: 12),
                  FilledButton.tonal(onPressed: onRetry, child: Text('重试')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfPreviewBundle {
  final PdfControllerPinch? pinchController;
  final PdfDocument? document;
  final bool isPaged;
  final int pagesCount;

  _PdfPreviewBundle({
    required this.pinchController,
    required this.document,
    required this.isPaged,
    required this.pagesCount,
  });

  void dispose() {
    pinchController?.dispose();
    unawaited(document?.close());
  }
}

class _VideoPreviewBundle {
  final VideoPlayerController video;
  final ChewieController chewie;

  _VideoPreviewBundle({required this.video, required this.chewie});

  void dispose() {
    chewie.dispose();
    video.dispose();
  }
}

class _AudioPreviewBundle {
  final AudioPlayer? player;
  final Uri? source;
  final Object? error;

  _AudioPreviewBundle({required this.player, required this.source, this.error});

  void dispose() {
    player?.dispose();
  }
}

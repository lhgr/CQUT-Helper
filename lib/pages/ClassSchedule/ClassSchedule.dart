import 'dart:async';
import 'package:cqut/pages/ClassSchedule/schedule_controller.dart';
import 'package:flutter/material.dart';
import '../../model/schedule_model.dart';
import 'widgets/schedule_header.dart';
import 'widgets/schedule_time_column.dart';
import 'widgets/schedule_course_grid.dart';

class ClassscheduleView extends StatefulWidget {
  ClassscheduleView({Key? key}) : super(key: key);

  @override
  _ClassscheduleViewState createState() => _ClassscheduleViewState();
}

class _ClassscheduleViewState extends State<ClassscheduleView> {
  final ScheduleController _controller = ScheduleController();
  ScheduleData? _currentScheduleData; // 当前显示的周数据

  // Getters for controller properties to minimize code changes
  Map<int, ScheduleData> get _weekCache => _controller.weekCache;
  List<String>? get _weekList => _controller.weekList;
  String? get _actualCurrentWeekStr => _controller.actualCurrentWeekStr;
  String? get _actualCurrentTermStr => _controller.actualCurrentTermStr;
  String? get _currentTerm => _controller.currentTerm;

  bool _loading = true; // 默认为 true，防止初始空数据渲染
  String? _error;

  // 用于周切换的 PageController
  PageController? _pageController;
  int _currentWeekIndex = 0; // 对应 weekList 的 0 基索引

  final double _headerHeight = 50.0;
  final double _timeColumnWidth = 30.0;
  final double _sessionHeight = 60.0;
  final List<Color> _lightColors = [
    Colors.blue.shade100,
    Colors.green.shade100,
    Colors.orange.shade100,
    Colors.purple.shade100,
    Colors.red.shade100,
    Colors.teal.shade100,
    Colors.pink.shade100,
    Colors.indigo.shade100,
  ];

  final List<Color> _darkColors = [
    Colors.blue.shade900,
    Colors.green.shade900,
    Colors.orange.shade900,
    Colors.purple.shade900,
    Colors.red.shade900,
    Colors.teal.shade900,
    Colors.pink.shade900,
    Colors.indigo.shade900,
  ];

  DateTime? _lastMessageTime;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    // 1. 优先尝试加载缓存以立即显示内容
    final cachedData = await _controller.loadFromCache();
    if (cachedData != null) {
      _processLoadedData(cachedData, isInitial: true);
    }

    // 2. 从网络加载以获取最新的“当前”周
    await _loadFromNetwork();
  }

  void _processLoadedData(ScheduleData data, {bool isInitial = false}) {
    if (data.weekNum == null || data.weekList == null) return;

    _controller.processLoadedData(data);

    setState(() {
      _currentScheduleData = data;

      // 初始化或更新 PageController
      final newIndex = _controller.weekList!.indexOf(data.weekNum!);
      if (newIndex != -1) {
        if (_pageController == null) {
          _currentWeekIndex = newIndex;
          _pageController = PageController(initialPage: newIndex);
        } else if (_currentWeekIndex != newIndex && !isInitial) {
          // 如果加载的特定周与当前索引不同
          // (例如来自学期选择器)，跳转到该周
          _currentWeekIndex = newIndex;
          _pageController!.jumpToPage(newIndex);
        }
      }
    });
  }

  Future<void> _loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool isPrefetch = false,
  }) async {
    if (!isPrefetch &&
        _controller.weekCache.containsKey(int.tryParse(weekNum ?? "") ?? -1)) {
      // 如果内存中有数据，直接更新视图 (除非正在刷新)
    }

    if (!isPrefetch) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _controller.loadFromNetwork(
        weekNum: weekNum,
        yearTerm: yearTerm,
      );

      if (!isPrefetch) {
        _processLoadedData(data);
        _schedulePrefetch(data);
      } else {
        // 对于预取，只更新缓存
        _controller.processLoadedData(data);
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (!isPrefetch) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (!isPrefetch && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _schedulePrefetch(ScheduleData currentData) {
    _controller.schedulePrefetch(currentData, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _ensureWeekLoaded(
    String weekNum,
    String yearTerm, {
    bool isPrefetch = false,
  }) async {
    await _controller.ensureWeekLoaded(weekNum, yearTerm);
    if (mounted) setState(() {});
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentWeekIndex = index;
    });

    if (_weekList == null || index < 0 || index >= _weekList!.length) return;

    final targetWeek = _weekList![index];
    final currentTerm = _currentScheduleData?.yearTerm ?? _currentTerm;

    // 如果我们有该周的缓存数据，立即更新标题
    final wInt = int.tryParse(targetWeek) ?? 0;
    if (_weekCache.containsKey(wInt)) {
      setState(() {
        _currentScheduleData = _weekCache[wInt];
      });
      _schedulePrefetch(_weekCache[wInt]!);
    } else {
      // 如果不在缓存中，尝试加载它 (将检查磁盘缓存然后是网络)
      // 我们是暂时将 currentScheduleData 设置为 null 还是保留上一个?
      // 最好保留上一个直到新的加载完成，但 PageView 会处理主体内容
      // 标题需要更新。我们可以构造一个虚拟的 ScheduleData 或者等待
      // 但我们确实有来自 _weekList 的周数
      if (currentTerm != null) {
        _loadFromNetwork(weekNum: targetWeek, yearTerm: currentTerm);
      }
    }
  }

  void _changeTerm(String term) {
    // 当学期改变时，我们基本重置所有内容
    // 加载新学期的第 1 周 (或者是当前周，如果是当前学期，但直接加载第 1 周或指定周更简单)
    // 需求说 "如果不是当前学期，默认为第 1 周"
    // 等等，如果我选择一个学期，没有逻辑很难知道它是否是当前学期
    // 我们直接加载目标周

    final currentWeek = _currentScheduleData?.weekNum;
    // 来自之前代码的逻辑：尽可能保持周数?
    // 实际上之前的代码：如果 term == currentTerm，保持周数，否则第 1 周
    // 但这里的 _currentTerm 可能是加载数据的学期

    // 我们直接加载数据
    _weekCache.clear();
    _loadFromNetwork(weekNum: '1', yearTerm: term);
  }

  // 显示选择器...
  void _showWeekPicker() {
    if (_weekList == null) return;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "选择周次",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _weekList!.length,
                  itemBuilder: (context, index) {
                    final week = _weekList![index];
                    final isCurrentWeek =
                        _actualCurrentTermStr != null &&
                        _currentScheduleData?.yearTerm ==
                            _actualCurrentTermStr &&
                        week == _actualCurrentWeekStr;

                    return ListTile(
                      title: Text(
                        "第 $week 周${isCurrentWeek ? ' (当前周)' : ''}",
                        textAlign: TextAlign.center,
                        style: isCurrentWeek
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _pageController?.jumpToPage(index);
                      },
                      selected: index == _currentWeekIndex,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTermPicker() {
    if (_currentScheduleData?.yearTermList == null) return;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "选择学期",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _currentScheduleData!.yearTermList!.length,
                  itemBuilder: (context, index) {
                    final term = _currentScheduleData!.yearTermList![index];
                    final isCurrentTerm = term == _actualCurrentTermStr;
                    return ListTile(
                      title: Text(
                        "$term${isCurrentTerm ? ' (当前学期)' : ''}",
                        textAlign: TextAlign.center,
                        style: isCurrentTerm
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _changeTerm(term);
                      },
                      selected: term == _currentScheduleData?.yearTerm,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _returnToCurrentWeek() {
    if (_actualCurrentWeekStr == null || _weekList == null) {
      // 回退：重新加载网络以查找当前
      _loadFromNetwork();
      return;
    }

    // 检查我们是否在正确的学期。如果不是，切换学期
    // 假设 actualCurrentWeek 仅对当前学期有效
    // 但我们不存储 "actualCurrentTerm"。我们可以假设初始加载的学期是当前的
    // 让我们遍历 weekList 来查找该周
    final index = _weekList!.indexOf(_actualCurrentWeekStr!);
    if (index != -1) {
      _pageController?.jumpToPage(index);
    } else {
      // 也许我们在不同的学期，重新加载初始数据
      _loadFromNetwork();
    }
  }

  void _showBoundaryMessage(String message) {
    final now = DateTime.now();
    if (_lastMessageTime != null &&
        now.difference(_lastMessageTime!) < Duration(seconds: 2)) {
      return;
    }
    _lastMessageTime = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((_currentScheduleData == null || _weekList == null) && _loading) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if ((_currentScheduleData == null || _weekList == null) && _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadFromNetwork(),
                icon: Icon(Icons.refresh),
                label: Text("重试"),
              ),
            ],
          ),
        ),
      );
    }

    // 防止 _weekList 为空时导致的 Null Check Error
    if (_weekList == null || _weekList!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 检查是否应该显示 FAB
    // 如果当前显示的周 != 实际当前周，则显示
    bool showFab = false;
    if (_actualCurrentWeekStr != null && _weekList != null) {
      final displayedWeek = _weekList![_currentWeekIndex];
      if (displayedWeek != _actualCurrentWeekStr) {
        showFab = true;
      }
      // 也要检查学期? 除了初始加载外，我们没有明确存储 currentTerm
      // 但如果 _weekList 包含 _actualCurrentWeekStr，我们可能在正确的学期 (或者周数重叠，但通常是唯一的，或者我们假设如此)
      // 实际上，如果我们切换学期，_weekList 会改变。如果 _weekList 不包含 _actualCurrentWeekStr，我们肯定在错误的学期 (或错误的周列表)
      if (!_weekList!.contains(_actualCurrentWeekStr)) {
        showFab = true;
      }
    }

    return Scaffold(
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _returnToCurrentWeek,
              child: Icon(Icons.today),
              tooltip: '返回本周',
            )
          : null,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            onPressed: _loading
                ? null
                : () => _loadFromNetwork(
                    weekNum: _weekList![_currentWeekIndex],
                    yearTerm: _currentScheduleData?.yearTerm,
                  ),
            icon: Icon(Icons.refresh),
          ),
        ],
        title: Column(
          children: [
            InkWell(
              onTap: _showWeekPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "第${_weekList![_currentWeekIndex]}周",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
            if (_currentScheduleData != null)
              InkWell(
                onTap: _showTermPicker,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${_currentScheduleData!.yearTerm}学期",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (notification.overscroll < 0) {
            // 开始边界
            if (_currentWeekIndex == 0) {
              _showBoundaryMessage("已经是第一周了");
            }
          } else if (notification.overscroll > 0) {
            // 结束边界
            if (_weekList != null &&
                _currentWeekIndex == _weekList!.length - 1) {
              _showBoundaryMessage("已经是最后一周了");
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          itemCount: _weekList!.length,
          itemBuilder: (context, index) {
            final weekStr = _weekList![index];
            final weekNum = int.tryParse(weekStr) ?? 0;
            final data = _weekCache[weekNum];

            if (data == null) {
              // 如果未加载，则触发加载?
              // 最好只显示此页面的加载指示器
              // 我们可以在这里触发加载，但 build 方法应该无副作用
              // 理想情况下 _onPageChanged 触发加载
              // 但是对于相邻页面的初始渲染?
              // 让我们依赖 _onPageChanged 和预取
              // 如果用户快速滑动，_onPageChanged 将触发

              // 我们可以检查是否应该在这里触发加载以提高鲁棒性
              if (!_loading && _currentScheduleData?.yearTerm != null) {
                // 推迟到下一帧
                Future.microtask(
                  () => _ensureWeekLoaded(
                    weekStr,
                    _currentScheduleData!.yearTerm!,
                  ),
                );
              }

              return Center(child: CircularProgressIndicator());
            }

            return Column(
              children: [
                ScheduleHeader(
                  scheduleData: data,
                  height: _headerHeight,
                  timeColumnWidth: _timeColumnWidth,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScheduleTimeColumn(
                          width: _timeColumnWidth,
                          sessionHeight: _sessionHeight,
                        ),
                        Expanded(
                          child: ScheduleCourseGrid(
                            events: data.eventList ?? [],
                            sessionHeight: _sessionHeight,
                            colors:
                                Theme.of(context).brightness == Brightness.dark
                                ? _darkColors
                                : _lightColors,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum RepoDownloadPhase { listing, downloading, zipping }

class RepoFolderDownloadProgress {
  final RepoDownloadPhase phase;
  final int current;
  final int total;
  final String? currentName;

  const RepoFolderDownloadProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.currentName,
  });
}

class RepoBatchDownloadProgress {
  final int done;
  final int total;
  final String? currentName;
  final int active;

  const RepoBatchDownloadProgress({
    required this.done,
    required this.total,
    this.currentName,
    required this.active,
  });
}


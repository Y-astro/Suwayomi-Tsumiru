// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../chapter/chapter_model.dart';

/// Structural equality lets the screen detect filter changes between builds.
typedef UpdatesFilter = ({
  bool? downloaded,
  bool? unread,
  bool? started,
  bool? bookmarked,
});

const UpdatesFilter kNoUpdatesFilter = (
  downloaded: null,
  unread: null,
  started: null,
  bookmarked: null,
);

/// Retained read rows stay visible but no longer occupy the filtered server page.
bool matchesUpdatesFilter(ChapterDto chapter, UpdatesFilter filter) {
  final user = chapter.user;
  return (filter.downloaded == null ||
          user.isDownloaded == filter.downloaded) &&
      (filter.unread == null || user.isRead != filter.unread) &&
      (filter.bookmarked == null || user.isBookmarked == filter.bookmarked) &&
      (filter.started == null ||
          (!user.isRead && (user.lastPageRead > 0) == filter.started));
}

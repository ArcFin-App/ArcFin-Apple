// SPDX-License-Identifier: AGPL-3.0-or-later

//
//  ArcfinWidgetsBundle.swift
//  ArcfinWidgets
//
//  Created by Puranjay Savar Mattas on 18/09/26.
//

import WidgetKit
import SwiftUI

@main
struct ArcfinWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DownloadLiveActivity()
        ContinueWatchingWidget()
        RecentlyAddedWidget()
        ResumeWatchingControl()
        DownloadsControl()
        DiscoverControl()
    }
}

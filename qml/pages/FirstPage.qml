import QtQuick 2.6
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import Nemo.Thumbnailer 1.0
import QtFeedback 5.0 // haptic effects
import Nemo.Notifications 1.0 // popup when an edit saved a new copy
import Sailfish.Share 1.0
import QtGraphicalEffects 1.0


Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int amountExtPartitions : 0
    property var distinctAlbums : []
    property string standardAlbum : "." + qsTr("UNSORTED")
    property string standardSearchAlbum : "." + qsTr("SEARCH")
    property string standardFavouritesAlbum : "." + qsTr("FAVOURITES")
    property string standardDuplicatesAlbum : "." + qsTr("DUPLICATES")
    property var standardScreenWidth
    property var standardScreenHeight
    property string currentAlbum : ""
    property string currentFolder : ""
    property string tempSearchText : ""
    property real minimumFolderListItemHeight : standardScreenWidth / (infoWidthDevider+2) // (infoWidthDevider === 2) ? Theme.itemSizeExtraLarge : Theme.itemSizeMedium
    property var minimumTimelineListItemHeight // done in Component.onCompleted
    property bool fileBrowserInstalled : false
    property bool multiSelectActive : false
    property real upperFreeHeight : Theme.itemSizeLarge
    property color buttonBackgroundColor: Theme.rgba(Theme.highlightDimmerColor, 1)
    property var hideBackColor : Theme.rgba(Theme.overlayBackgroundColor, 0.9)
    property bool delegateMenuOpen : false
    property int imagesWorkload2Rescan : 75

    // image list generation and checks against db
    property int settingUseExif : 0 //parseInt(storageItem.getSetting("infoTimeUseExifAlbum", 0))
    property bool refreshingExifCache : false // python tells us when the exif cache gets rebuilt from scratch
    property string deleteRequestSourcePage : "" // which page a delete came from, list cleanup happens once python reports back
    property string currentFolderAlbumFilter : "" // when set, the opened folder view only shows images of this album
    property string timelineAlbumFilter : "" // when set, the timeline only shows images of this album (via idListModelTimelineFiltered)
    property int timelineSelectedTotal : 0 // selected images in the timeline while multiSelectActive
    property var expandedAlbumPrefixes : ({}) // which album name prefixes ("Foo", "Foo / Bar") are expanded in the album tree
    property string lastNotifiedImagePath : "" // tapping the notification jumps to this image in the timeline
    property string pendingTimelineJumpPath : "" // the tapped image was not scanned in yet, the jump retries after the scan
    property bool pendingDuplicateSearch : false // "Refresh duplicates" rescans first, the duplicate search chains after the scan

    Connections {
        // a counter avoids resetting the source inside its own change handler, which is a binding loop
        target: idApplicationWindow
        onNotificationTapCounterChanged: {
            if (lastNotifiedImagePath !== "") {
                showImageInTimeline( lastNotifiedImagePath )
            }
        }
    }
    property string timelineSortDirection : "0" // mirrors infoTimeLineDirectionIndex, "0" = newest first
    property var dbFavouritesArray : [] //storageItem.getAllStoredKeywords( "noFilesAvailable" )
    property var dbPathAlbumsArray : [] //storageItem.getAllStoredImagesAlbums( "noPathAvailable", "noInfoAvailable" )

    // python image functions
    property bool pillowAvailable : true



    Component.onCompleted: {
        py.getAmountExtPartitions() // -> result will trigger py.scanForImages()
        py.checkCMDexistance("harbour-file-browser")
        standardScreenWidth = page.width
        standardScreenHeight = page.height
        minimumTimelineListItemHeight = standardScreenWidth / infoWidthDevider
    }

    Item {
        id: idWatchdog_reloadSettingsFromDB
        enabled: ( reloadDBSettings === true ) ? true : false
        onEnabledChanged: {
            if ( enabled === true ) { // on_enter
                finishedLoading = false
                settingUseExif = parseInt(storageItem.getSetting("infoTimeUseExifAlbum", 0))
                amountDetails = parseInt(storageItem.getSetting("infoTimeShowDetailsIndex", 0))
                infoWidthDevider = parseInt(storageItem.getSetting("infoWidthDevider", 3))
                infoActivateCoverImages = parseInt(storageItem.getSetting("infoActivateCoverImages", 0))
                coverImageChangeInterval = parseInt(storageItem.getSetting("coverImageChangeInterval", 5000))
                minimumTimelineListItemHeight = standardScreenWidth / infoWidthDevider
                //console.log("setting_rescan_status: " + settingsRequireRescanImages)
                if (settingsRequireRescanImages === true) {
                    clearAllLists()
                    idDelayTimerApplySettingsScan4Images.start()
                }
                settingsRequireRescanImages = false
                finishedLoading = true
            }
        }
    }
    Item {
        id: idWatchdog_clearDBoldEntries
        enabled: ( clearDBoldEntries === true ) ? true : false
        onEnabledChanged: {
            if ( enabled === true ) { // on_enter
                py.checkDB_fileExistance()
            }
        }
    }
    HapticsEffect {id: rumbleEffect
        attackIntensity: 1.0
        attackTime: 250
        intensity: 1.0
        duration: 100
        fadeTime: 250
        fadeIntensity: 0.0
    }
    RemorsePopup {
        height: Theme.itemSizeLarge * 1.3
        id: remorse
    }
    Item {
        visible: false
        Image {
            visible: false
            id: idImageSizeHelper
            cache: false
            source: ""
        }
    }
    Component {
        id: datePickerComponent
        DatePickerDialog {}
    }
    Component {
        id: albumPage
        AlbumPage {}
    }
    Component {
        id: fileDetailPage
        FileDetailPage{}
    }
    Component {
        id: viewPage
        ViewPage {}
    }
    BannerToAlbum {
        id: bannerToAlbum
    }
    BannerRename {
        id: bannerRename
    }
    BannerSearch {
        id: bannerSearch
    }
    BannerResize {
        id: bannerResize
    }
    BannerGif {
        id: bannerGif
    }
    ListModel {
        id: idListModelImages
    }
    ListModel {
        id: idListModelImagesAlbum
    }
    ListModel {
        id: idListModelAlbums
    }
    ListModel {
        id: idListModelFolders
        property string sortColumnName: "folder_name"
        function swap(a,b) {
            if (a<b) {
                move(a,b,1);
                move (b-1,a,1);
            } else if (a>b) {
                move(b,a,1);
                move (a-1,b,1);
            }
        }
        function partition(begin, end, pivot) {
            var piv=get(pivot)[sortColumnName];
            swap(pivot, end-1);
            var store=begin;
            var ix;
            for(ix=begin; ix<end-1; ++ix) {
                if(get(ix)[sortColumnName] < piv) {
                    swap(store,ix);
                    ++store;
                }
            }
            swap(end-1, store);
            return store;
        }
        function qsort(begin, end) {
            if(end-1>begin) {
                var pivot=begin+Math.floor(Math.random()*(end-begin));
                pivot=partition( begin, end, pivot);
                qsort(begin, pivot);
                qsort(pivot+1, end);
            }
        }
        function quick_sort() {
            qsort(0,count)
        }
    }
    ListModel {
        id: idListModelImagesFolder
    }
    ListModel {
        id: idListModelSearch
    }
    ListModel {
        id: idListModelFavourites
    }
    ListModel {
        id: idListModelTimelineFiltered
    }
    Notification {
        id: idNotificationEditSaved
        isTransient: true // the gif-created publish flips this off so its notification stays tappable in the events view
        urgency: Notification.Low
        // tapping the notification is a dbus remote action, the call lands in the DBusAdaptor in harbour-timeline.qml
        remoteActions: [ {
            "name": "default",
            "service": "harbour.timeline",
            "path": "/harbour/timeline",
            "iface": "harbour.timeline",
            "method": "openNotifiedImage"
        } ]
    }
    ListModel {
        id: idListModelDuplicates
    }
    ListModel {
        id: idListModelAlbumTree
    }
    ShareAction {
        id: shareActionZip
        mimeType: "application/zip"
    }
    Timer {
        // needed for fully returning to firstPage from settingsPage before scanning starts and blocks UI
        id: idDelayTimerApplySettingsScan4Images
        interval: 500
        running: false
        repeat: false
        onTriggered: {
            clearAllLists() // needed?
            py.scanForImages()
        }
    }
    Timer {
        id: idCoverImageChangeTimer
        property bool firstRandomization : false
        interval: coverImageChangeInterval // [ms}
        running: infoActivateCoverImages === 1 && finishedLoading
        repeat: true
        triggeredOnStart: firstRandomization // bugfix: only run on very first time without delay, but when opening+closing context menu in albums, do not trigger randomization
        onTriggered: {
            firstRandomization = false
            randomizeCoverAlbumFolderArt()
        }
    }


    Python {
        id: py
        Component.onCompleted: {
            addImportPath(Qt.resolvedUrl('../py'));
            importModule('timelinex', function () {});

            // Handlers = Signals to do something in QML whith received Infos from pyotherside
            setHandler('debugPythonLogs', function(i) {
                console.log(i)
            });
            setHandler('scanProgress', function(someCounter, imagesTotalAmount) {
                currentlyScannedImage = someCounter
                maxScannedImages = imagesTotalAmount
            });
            setHandler('refreshingExifCache', function() {
                refreshingExifCache = true
            });
            setHandler('returnSortedImageList2Model', function(fileList) {
                //idListModelImages.clear()
                //idListModelImagesAlbum.clear()

                // build lookup maps once instead of scanning the db arrays for every single image
                var monthNamesArray = [ qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"), qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"), qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December") ]
                var favouritesMap = ({})
                for (var j = 0; j < dbFavouritesArray.length; j++) {
                    favouritesMap[dbFavouritesArray[j]] = true
                }
                var albumsMap = ({})
                for (j = 0; j < dbPathAlbumsArray.length; j++) {
                    albumsMap[dbPathAlbumsArray[j][0]] = dbPathAlbumsArray[j][1]
                }

                // now go through file list and add all info
                for(var i = 0; i < fileList.length; i++) {
                    var month2text = monthNamesArray[fileList[i][3]-1]
                    var newPathArray = fileList[i][1].split("/")
                    var folderPath = (newPathArray.slice(0, newPathArray.length-1)).join("/") + "/"
                    var fileName = newPathArray.slice(-1)[0]
                    var estimatedSize = Math.round ( (parseInt(fileList[i][5])/1024/1024) * 100) / 100
                    var exifAlbum = fileList[i][6]

                    // check if image is a favourite in DB
                    var isFavourite = (favouritesMap[fileList[i][1]] === true) ? "true" : "false"

                    // check if image has album assigned in DB
                    var inAlbum = (albumsMap[fileList[i][1]] !== undefined) ? albumsMap[fileList[i][1]] : standardAlbum

                    // overwrite this value in case album taken from EXIF
                    if ( (settingUseExif !== 0) && (exifAlbum !== "|||") ) {
                        inAlbum = exifAlbum
                    }

                    // add info to different lists
                    idListModelImages.append({
                                                "creationDateMS" : fileList[i][0],
                                                "filePath" : fileList[i][1],
                                                "monthYear" : month2text + " " + fileList[i][2],
                                                "day" : fileList[i][4],
                                                "folderPath" : folderPath,
                                                "fileName" : fileName,
                                                "estimatedSize" : estimatedSize,
                                                "album" : inAlbum,
                                                "selected" : false,
                                                "exifInfo" : fileList[i][6],
                                                "isSearchResult" : false, //true???
                                                "timestampSource" : fileList[i][7],
                                                "isFavourite" : isFavourite
                                             })
                    if (isFavourite === "true") {
                        idListModelFavourites.append({
                                                "creationDateMS" : fileList[i][0],
                                                "filePath" : fileList[i][1],
                                                "monthYear" : month2text + " " + fileList[i][2],
                                                "day" : fileList[i][4],
                                                "folderPath" : folderPath,
                                                "fileName" : fileName,
                                                "estimatedSize" : estimatedSize,
                                                "album" : inAlbum,
                                                "selected" : false,
                                                "exifInfo" : fileList[i][6],
                                                "isSearchResult" : false,
                                                "timestampSource" : fileList[i][7],
                                                "isFavourite" : isFavourite,
                                                "listModelImages_baseIndex" : i
                                             })
                    }
                }

                // duplicates results survive the rescan, drop vanished files and refresh the stored positions first
                remapBaseIndexes()

                // re-count items still left, search results should be kept
                countDistinctAlbums()
                countDistinctFolders()
                randomizeDistinctFoldersArray()
                randomCoverImage()

                // re-fill a folder or album grid that may still be open, a rescan cleared its model and only rebuilt the main lists
                if (currentFolder !== "") { getImagesInFolder(currentFolder) }
                if (currentAlbum !== "") { getImagesInAlbum(currentAlbum) }

                fileList = []
                dbFavouritesArray = []
                dbPathAlbumsArray = []
                finishedLoading = true //done creating list models

                // a notification tap may have arrived while this scan was still running
                if (pendingTimelineJumpPath !== "") {
                    var retryJumpPath = pendingTimelineJumpPath
                    pendingTimelineJumpPath = ""
                    showImageInTimeline( retryJumpPath )
                }

                // "Refresh duplicates" wants the duplicate search run against the fresh scan
                if (pendingDuplicateSearch === true) {
                    pendingDuplicateSearch = false
                    runDuplicateSearch()
                }
            });
            setHandler('goToDateIndex', function( targetListIndex ) {
                idListViewTimeline.positionViewAtIndex( targetListIndex, ListView.Center)
            });
            setHandler('returnEXIFinfoList', function( exifInfoList, availableExifInfosList, filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite ) {
                pageStack.animatorPush(fileDetailPage, {
                                           exifList : exifInfoList,
                                           availableExifInfosList : availableExifInfosList,
                                           filePath : filePath,
                                           fileName : fileName,
                                           folderPath : folderPath,
                                           creationDateMS : creationDateMS,
                                           estimatedSize : estimatedSize,
                                           album : album,
                                           imageWidth : imageWidth,
                                           imageHeight : imageHeight,
                                           timestampSource : timestampSource,
                                           isFavourite : isFavourite
                })
                //console.log(availableExifInfosList)
            });
            setHandler('finishedRenaming', function( newPath ) {
                console.log( newPath )
            });
            setHandler('removeEntryFromDB', function( inWhichTable, filePath ) {
                if (inWhichTable === "inAlbumTable") {
                    storageItem.removeAlbum(filePath)
                }
                else { // inWhichTable === "inKeywordsTable"
                    storageItem.removeKeywords(filePath)
                }
                //console.log(inWhichTable + ": " + filePath)
            });
            setHandler('finishedRemovingEntriesFromDB', function() {
                clearDBoldEntries = false
            });
            setHandler('returnCommandExists', function( command ) {
                if (command === "harbour-file-browser") {
                    fileBrowserInstalled = true
                }
                else {
                    console.log(command)
                }
            });
            setHandler('returnAmountExtPartitions', function( amountExternalPartitions ) {
                amountExtPartitions = amountExternalPartitions
                py.scanForImages() // triggered only here on startUp, otherwise scanning for external drives might take too long and would miss SD cards
            });
            setHandler('zipFileCreated', function( targetPath ) {
                //console.log(targetPath)
                finishedLoading = true
                shareActionZip.resources = [targetPath]
                shareActionZip.trigger()
            });
            setHandler('finishedWritingMetadata', function() {
                //console.log("finished writing metadata")
            });
            setHandler('pillowNotAvailable', function( reason ) {
                if (reason === "tooOld") {
                    console.log("Pillow is available but seems too OLD")
                }
                else {
                    console.log("Pillow is NOT available")
                }
                pillowAvailable = false
            });
            setHandler('batchResizeProgress', function( progressResizing ) {
                if (progressResizing >= 100) {
                    finishedLoading = true
                }
            });
            setHandler('returnDeletedFiles', function(deletedPathArray, failedPathArray) {
                if (failedPathArray.length > 0) {
                    console.log("could not delete " + failedPathArray.length + " file(s): " + failedPathArray)
                }
                removeDeletedFilesFromLists(deletedPathArray)
            });
            setHandler('returnDuplicateImages', function(duplicateGroups) {
                idListModelDuplicates.clear()
                var pathIndexMap = ({})
                for (var i = 0; i < idListModelImages.count; i++) {
                    pathIndexMap[idListModelImages.get(i).filePath] = i
                }
                for (var g = 0; g < duplicateGroups.length; g++) {
                    for (var m = 0; m < duplicateGroups[g].length; m++) {
                        var baseIndex = pathIndexMap[duplicateGroups[g][m]]
                        if (baseIndex !== undefined) {
                            var imageItem = idListModelImages.get(baseIndex)
                            idListModelDuplicates.append({
                                "creationDateMS" : imageItem.creationDateMS,
                                "filePath" : imageItem.filePath,
                                "monthYear" : imageItem.monthYear,
                                "day" : imageItem.day,
                                "folderPath" : imageItem.folderPath,
                                "fileName" : imageItem.fileName,
                                "estimatedSize" : imageItem.estimatedSize,
                                "album" : imageItem.album,
                                "selected" : false,
                                "exifInfo" :  imageItem.album,
                                "isSearchResult" : false,
                                "timestampSource" : imageItem.timestampSource,
                                "isFavourite" : imageItem.isFavourite,
                                "listModelImages_baseIndex" : baseIndex,
                                "duplicateGroup" : g
                            })
                        }
                    }
                }
                dropLonelyDuplicateGroups() // a member may not be in the main list at all
                countDistinctAlbums()
                // an open DUPLICATES album page shows idListModelImagesAlbum, re-fill it with the fresh results
                if (currentAlbum === standardDuplicatesAlbum) {
                    getImagesInAlbum( standardDuplicatesAlbum )
                }
                finishedLoading = true
            });
            setHandler('gifCreated', function(gifPath) {
                if (gifPath === "") { // failed, nothing was created and no source image was touched
                    finishedLoading = true
                    lastNotifiedImagePath = ""
                    idNotificationEditSaved.isTransient = true
                    idNotificationEditSaved.urgency = Notification.Low
                    idNotificationEditSaved.summary = ""
                    idNotificationEditSaved.body = ""
                    idNotificationEditSaved.previewSummary = qsTr("GIF creation failed")
                    idNotificationEditSaved.previewBody = ""
                    idNotificationEditSaved.publish()
                }
                else {
                    if (pendingGifAlbum !== "") {
                        storageItem.addAlbum(gifPath, pendingGifAlbum)
                    }
                    pendingGifAlbum = ""
                    lastNotifiedImagePath = gifPath
                    idNotificationEditSaved.isTransient = false // stays in the events view, tapping it jumps to the gif
                    idNotificationEditSaved.urgency = Notification.Normal // low urgency would not show a banner for a non-transient notification
                    idNotificationEditSaved.summary = qsTr("GIF created")
                    idNotificationEditSaved.body = gifPath.split("/").pop()
                    idNotificationEditSaved.previewSummary = qsTr("GIF created")
                    idNotificationEditSaved.previewBody = gifPath.split("/").pop()
                    idNotificationEditSaved.publish()
                    clearAllLists()
                    py.scanForImages()
                }
            });
            setHandler('editedImageSaved', function(copyPath) {
                lastEditedImagePath = copyPath
                lastNotifiedImagePath = ""
                idNotificationEditSaved.isTransient = true
                idNotificationEditSaved.urgency = Notification.Low
                idNotificationEditSaved.summary = ""
                idNotificationEditSaved.body = ""
                idNotificationEditSaved.previewSummary = qsTr("Saved as new copy")
                idNotificationEditSaved.previewBody = copyPath.split("/").pop()
                idNotificationEditSaved.publish()
                // bring the copy into all lists, the guard keeps a bulk edit from stacking rescans
                if (finishedLoading === true) {
                    clearAllLists()
                    py.scanForImages()
                }
            });
            setHandler('updateImage', function() {
                reloadImage = true
                reloadImage = false
            });
            setHandler('updateSingleFileSize', function(filePath, newFileSize) {
                var estimatedSize = Math.round ( (parseInt(newFileSize)/1024/1024) * 100) / 100
                // update main listmodelImages
                for (var i = 0; i < idListModelImages.count; i++) {
                    if (idListModelImages.get(i).filePath === filePath) {
                        console.log("listmodelImages ID: " + i)
                        idListModelImages.setProperty(i, "estimatedSize", estimatedSize)
                    }
                }
                // update current album images list if available
                for (i = 0; i < idListModelImagesAlbum.count; i++) {
                    if (idListModelImagesAlbum.get(i).filePath === filePath) {
                        console.log("listmodel album images ID: " + i)
                        idListModelImagesAlbum.setProperty(i, "estimatedSize", estimatedSize)
                    }
                }
                // update current folder images list if available
                for (i = 0; i < idListModelImagesFolder.count; i++) {
                    if (idListModelImagesFolder.get(i).filePath === filePath) {
                        console.log("listmodel folder images ID: " + i)
                        idListModelImagesFolder.setProperty(i, "estimatedSize", estimatedSize)
                    }
                }
                // update listmodelFavourites if available
                for (i = 0; i < idListModelFavourites.count; i++) {
                    if (idListModelFavourites.get(i).filePath === filePath) {
                        console.log("listmodel favourites ID: " + i)
                        idListModelFavourites.setProperty(i, "estimatedSize", estimatedSize)
                    }
                }
                // update listmodelSearch if available
                for (i = 0; i < idListModelSearch.count; i++) {
                    if (idListModelSearch.get(i).filePath === filePath) {
                        console.log("listmodel search ID: " + i)
                        idListModelSearch.setProperty(i, "estimatedSize", estimatedSize)
                    }
                }
            });
        }

        // image editing operations
        function imageRotateFunction( filePath, targetAngle ) {
            call("timelinex.imageRotateFunction", [ filePath, targetAngle ])
        }
        function imageFlipMirrorFunction( filePath, targetDirection ) {
            call("timelinex.imageFlipMirrorFunction", [ filePath, targetDirection ])
        }
        function imageCropFunction( filePath, rectX, rectY, rectWidth, rectHeight, scaleFactor ) {
            call("timelinex.imageCropFunction", [ filePath, rectX, rectY, rectWidth, rectHeight, scaleFactor ])
        }
        function imageColorizeFunction( filePath, brightnessFactor, contrastFactor ) {
            call("timelinex.imageColorizeFunction", [ filePath, brightnessFactor, contrastFactor ])
        }
        function imageResizeFunction( filePath, targetWidth, targetHeight, targetDirection ) {
            finishedLoading = false
            call("timelinex.imageResizeFunction", [ filePath, targetWidth, targetHeight ])
        }
        function imageBulkResizeFunction( imagePathsList, targetWidth, targetHeight, targetDirection ) {
            finishedLoading = false
            call("timelinex.imageBulkResizeFunction", [ imagePathsList, targetWidth, targetHeight, targetDirection ])
        }
        function imagePaintFunction ( filePath, imageRatioSourceScreen, freeDrawPolyCoordinates, lineColorArray, lineWidthArray ) {
            call("timelinex.imagePaintFunction", [ filePath, imageRatioSourceScreen, freeDrawPolyCoordinates, lineColorArray, lineWidthArray ])
        }

        // file operations
        function scanForImages() {
            finishedLoading = false
            refreshingExifCache = false
            runSlideshowTimer = false
            timelineAlbumFilter = "" // a rescan rebuilds the main list, stored filter indexes would go stale
            idListModelTimelineFiltered.clear()
            // the following part could also be included on the receiving end but saves some time if done here
            idListModelImages.clear()
            idListModelImagesAlbum.clear()
            dbFavouritesArray = storageItem.getAllStoredKeywords( "noFilesAvailable" )
            dbPathAlbumsArray = storageItem.getAllStoredImagesAlbums( "noPathAvailable", "noInfoAvailable" )
            // important preparational info
            var folders2scanHOME = (storageItem.getSetting("infoFolders2scanHOME", "/Downloads|||/Pictures|||/Documents|||/android_storage")).split("|||")
            if (amountExtPartitions !== 0) {
                var folders2scanEXTERN = (storageItem.getSetting("infoFolders2scanEXTERN", "/Download|||/DCIM|||/Android")).split("|||")
            }
            else {
                folders2scanEXTERN = ""
            }
            var sdCards2scanEXTERN = (storageItem.getSetting("sdCards2scanEXTERN", "1|||1|||1")).split("|||")
            var showDirection = storageItem.getSetting("infoTimeLineDirectionIndex", "0")
            timelineSortDirection = showDirection
            var creationModificationDate = parseInt(storageItem.getSetting("infoTimeCreationModification", 0))
            var showHiddenFiles = parseInt(storageItem.getSetting("infoTimeHiddenFiles", 0))
            settingUseExif = parseInt(storageItem.getSetting("infoTimeUseExifAlbum", 0)) // 0 = no scanning, saves time // 1 = metadata // 2= filename parsing and metadata
            call("timelinex.scanForImages", [folders2scanHOME, folders2scanEXTERN, sdCards2scanEXTERN, showDirection, creationModificationDate, showHiddenFiles, settingUseExif])
        }
        function getEXIFdata( filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite) {
            call("timelinex.getEXIFdata", [ filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite ])
        }
        function findClosestDate( targetDate ) {
            var datesItems = []
            for (var k = 0; k < idListModelImages.count; k++) {
                //console.log(idListModelImages.get(k).creationDateMS)
                datesItems.push(idListModelImages.get(k).creationDateMS)
            }
            var thisDateLocale = new Date(targetDate).toLocaleDateString(Qt.locale("de_DE"), "dd. MMMM yyyy") // weekday "dddd"
            var thisDateMS = new Date(targetDate).getTime() / 1000
            //console.log(thisDateLocale)
            //console.log(thisDateMS)
            call("timelinex.findClosestDate", [datesItems, thisDateMS])
        }
        function deleteFilesFunction( deletePathArray ) {
            call("timelinex.deleteFilesFunction", [ deletePathArray ])
        }
        function findDuplicateImages( allPathsArray, tolerance ) {
            call("timelinex.findDuplicateImages", [ allPathsArray, tolerance ])
        }
        function createAnimatedGif( gifPathsArray, frameDurationMS, targetStorageMedia, targetFolder, gifFileName ) {
            call("timelinex.createAnimatedGif", [ gifPathsArray, frameDurationMS, targetStorageMedia, targetFolder, gifFileName ])
        }
        function renameOriginalFunction( currentPath ) {
            //var currentPath = "/" + origImageFilePath.replace(/^(file:\/{3})|(qrc:\/{2})|(http:\/{2})/,"")
            //var newPath = "some_path.new"
            //call("graphx.renameOriginalFunction", [ currentPath, newPath ])
        }
        function checkDB_fileExistance() {
            // clear empty entries from "album" table
            var storedFiles_inDB_Array = storageItem.getAllStoredImages( "noFilesAvailable" )
            for (var j = 0; j < storedFiles_inDB_Array.length; j++) {
                call("timelinex.checkFileExistence", [ "inAlbumTable", storedFiles_inDB_Array[j] ])
            }
            //console.log(storedFiles_inDB_Array + "\n")
            // clear also empty entries from "keywords" table
            var storedKeywords_inKEYWORDS_Array = storageItem.getAllStoredKeywords( "noFilesAvailable" )
            for (j = 0; j < storedKeywords_inKEYWORDS_Array.length; j++) {
                call("timelinex.checkFileExistence", [ "inKeywordsTable", storedKeywords_inKEYWORDS_Array[j] ])
            }
            //console.log(storedKeywords_inKEYWORDS_Array.length )
            //console.log(storedKeywords_inKEYWORDS_Array)
        }
        function checkCMDexistance( command ) {
            call("timelinex.checkCMDexistance", [ command ])
        }
        function runCMDtool( command ) {
            call("timelinex.runCMDtool", [ command ])
        }
        function getAmountExtPartitions () {
            call("timelinex.getAmountExtPartitions", [])
        }
        function insertMetadataKeywords ( tags, filePath ) {
            if (infoStrictReadOnly !== 0) { return } // strict read-only mode never writes into image files
            var storeWhere = "in_IPTC"
            call("timelinex.insertMetadataKeywords", [ tags, filePath, storeWhere ])
        }
        function removeMetadataKeywords ( filePath ) {
            if (infoStrictReadOnly !== 0) { return } // strict read-only mode never writes into image files
            var storeWhere = "in_IPTC"
            call("timelinex.removeMetadataKeywords", [ filePath, storeWhere ])
        }
        function packZipImagesTmp ( imagePathsList ) {
            if (imagePathsList.length > 4) {
                finishedLoading = false
                call("timelinex.packZipImagesTmp", [ imagePathsList ])
            }
        }
        function editEXIFdata ( filePath, ifdZone, tagNr, tagName, tagValue ) {
            if (infoStrictReadOnly !== 0) { return } // strict read-only mode never writes into image files
            //finishedLoading = false
            call("timelinex.editEXIFdata", [ filePath, ifdZone, tagNr, tagName, tagValue ])
        }

        onError: {
            //console.log('python error: ' + traceback) //when an exception is raised, this error handler will be called
        }
        onReceived: {
            //console.log('got message from python: ' + data) //asychronous messages from Python arrive here; done there via pyotherside.send()
        }
    } // end Python


    SilicaFlickable {
        id: idSilicaFlickableFirstPage
        anchors.fill: parent
        anchors.bottomMargin: idFooterRow.height
        // horizontal drag room for side-swiping between the views, vertical scrolling stays with the views themselves
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: width * 3
        contentHeight: height
        onWidthChanged: contentX = width // also re-centers on orientation changes
        onMovementEnded: {
            if (contentX > width + width / 4) { switchViewBySwipe(1) }
            else if (contentX < width - width / 4) { switchViewBySwipe(-1) }
            contentX = width
        }

        SilicaListView {
            id: idListViewTimeline
            visible: currentView === "timeline"
            enabled: visible
            x: idSilicaFlickableFirstPage.width // the middle slot of the horizontal drag room is the resting position
            width: idSilicaFlickableFirstPage.width
            height: idSilicaFlickableFirstPage.height
            clip: true
            spacing: Theme.paddingSmall
            quickScroll: false
            //header:
            footer: Item {
                width: parent.width
                height: (isPortrait) ? upperFreeHeight/3 : 0
            }

            //VerticalScrollDecorator {}
            ScrollBar {
                id: idScrollBarDate
                enabled: true
                labelVisible: true
                //topPadding: (isPortrait) ? upperFreeHeight/3 : 0
                topPadding: (isPortrait) ? upperFreeHeight : 0
                bottomPadding: (isPortrait) ? upperFreeHeight/3 : 0
                labelModelTag: "monthYear"
                visible: (parent.visibleArea.heightRatio < 1.0) && (idPulldownMenu.active === false) && (idPushUpMenu.active === false) && (delegateMenuOpen === false)
            }
            PullDownMenu {
                id: idPulldownMenu
                quickSelect: true
                enabled: finishedLoading === true

                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: {
                        // full rescan, picks up images that arrived outside the app and re-counts albums and folders
                        clearAllLists()
                        py.scanForImages()
                    }
                }
                MenuItem {
                    text: qsTr("Jump to Date")
                    onClicked: {
                        var dialog = pageStack.push(datePickerComponent, { })
                        dialog.accepted.connect( function () {
                            py.findClosestDate(dialog.date)
                        } )
                    }
                }
                MenuItem {
                    text: (timelineSortDirection === "0") ? qsTr("Show oldest first") : qsTr("Show newest first")
                    onClicked: {
                        reverseTimelineOrder()
                    }
                }
                MenuItem {
                    text: (timelineAlbumFilter !== "") ? qsTr("Show all") : qsTr("Filter by album")
                    onClicked: {
                        if (timelineAlbumFilter !== "") {
                            clearTimelineAlbumFilter()
                        }
                        else {
                            bannerToAlbum.notify( Theme.highlightDimmerColor, Theme.itemSizeHuge, [], "fromTimeline", "triggeredOnFirstPage", true )
                        }
                    }
                }

            }
            BusyIndicator {
                anchors.centerIn: parent
                running: finishedLoading === false
                size: BusyIndicatorSize.Large
            }
            Label {
                visible: !finishedLoading
                enabled: visible
                width: parent.width
                height: upperFreeHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight //HCenter
                rightPadding: Theme.paddingLarge // * 2
                leftPadding: rightPadding
                color: finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor
                elide: Text.ElideRight
                text: (refreshingExifCache ? qsTr("Refreshing EXIF cache") + " " : "") + (currentlyScannedImage + "/" + maxScannedImages)
            }

            section.property: ("monthYear")
            section.criteria: ViewSection.FullString
            section.delegate: Text {
                text: section
                height: upperFreeHeight
                width: parent.width
                rightPadding: 2* Theme.paddingLarge
                leftPadding: rightPadding
                color: Theme.highlightColor
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
            }

            model: (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
            delegate: ListItem {
                width: parent.width
                contentHeight: Math.max( idListRowTimelineDescription.height, minimumTimelineListItemHeight - Theme.paddingSmall )
                contentWidth: (idListViewTimeline.visibleArea.heightRatio < 1.0) ? (parent.width - Theme.paddingLarge*2) : (parent.width)
                onClicked:  {
                    // when multiselection is active a tap toggles the selection instead of opening the image
                    if (multiSelectActive === true) {
                        if (selected) {
                            selected = false
                            timelineSelectedTotal = timelineSelectedTotal - 1
                        }
                        else {
                            selected = true
                            timelineSelectedTotal = timelineSelectedTotal + 1
                        }
                        return
                    }
                    var currentImageIndex = index
                    var currentTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                    var allCurrentModelImagePathsArray = []
                    for (var j = 0; j < currentTimelineModel.count; j++) {
                        allCurrentModelImagePathsArray.push(currentTimelineModel.get(j).filePath)
                    }
                    pageStack.animatorPush(viewPage, {
                                               upperFreeHeight : upperFreeHeight,
                                               allCurrentModelImagePathsArray : allCurrentModelImagePathsArray,
                                               currentImageIndex : currentImageIndex,
                                           })
                }

                function removeFile( filePathArray ) {
                    remorseAction(qsTr("Delete file?"), function() {
                        deleteThisImage( filePathArray, "firstPage" )
                        unselectAll()
                    })
                }

                menu: Component {
                    ContextMenu {
                        MenuItem {
                            visible: (multiSelectActive === false) || (timelineSelectedTotal > 0)
                            enabled: visible
                            text: qsTr("Set Album")
                            onClicked: {
                                var chosenFilesArray = []
                                if (multiSelectActive === true) {
                                    var activeTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                    for (var j = 0; j < activeTimelineModel.count; j++) {
                                        if (activeTimelineModel.get(j).selected === true) {
                                            var rowBaseIndex = (timelineAlbumFilter !== "") ? activeTimelineModel.get(j).listModelImages_baseIndex : j
                                            chosenFilesArray.push( [0, activeTimelineModel.get(j).filePath, rowBaseIndex] )
                                            activeTimelineModel.setProperty(j, "selected", false)
                                        }
                                    }
                                    multiSelectActive = false
                                    timelineSelectedTotal = 0
                                }
                                else {
                                    // with an active filter the delegate index is not the index into idListModelImages
                                    var baseIndex = (timelineAlbumFilter !== "") ? model.listModelImages_baseIndex : index
                                    chosenFilesArray.push([0,filePath,baseIndex])
                                }
                                bannerToAlbum.notify( Theme.highlightDimmerColor, Theme.itemSizeHuge, chosenFilesArray, "fromTimeline", "triggeredOnFirstPage" )
                            }
                        }
                        MenuItem {
                            visible: (multiSelectActive === false) || (timelineSelectedTotal > 0)
                            enabled: visible
                            text: (isFavourite !== "true") ? qsTr("Set Favourite") : qsTr("From Favourite")
                            onClicked: {
                                // only use isFavourite info from the item currently touched
                                if (isFavourite !== "true") {
                                    var updateType = "addFavourite"
                                }
                                else {
                                    updateType = "removeFavourite"
                                }
                                var chosenFilesArray = []
                                if (multiSelectActive === true) {
                                    var activeTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                    for (var j = 0; j < activeTimelineModel.count; j++) {
                                        if (activeTimelineModel.get(j).selected === true) {
                                            chosenFilesArray.push(activeTimelineModel.get(j).filePath)
                                            addTimelineRowToFavourites(activeTimelineModel, j, updateType)
                                        }
                                    }
                                }
                                else {
                                    chosenFilesArray.push(filePath)
                                    var singleModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                    addTimelineRowToFavourites(singleModel, index, updateType)
                                }
                                updateAllLists_isFavourite ("fromFirstPage" , updateType, chosenFilesArray)
                                if (multiSelectActive === true) {
                                    unselectAll()
                                }
                            }
                        }
                        MenuItem {
                            enabled: multiSelectActive === false
                            visible: enabled
                            text: qsTr("Open with")
                            onClicked: {
                                Qt.openUrlExternally("file:///" + filePath)
                            }
                        }
                        MenuItem {
                            visible: (multiSelectActive === false) || (timelineSelectedTotal > 0)
                            enabled: visible
                            text: qsTr("Share")
                            ShareAction {
                                id: shareAction
                                mimeType: "image/*"
                            }
                            onClicked: {
                                var sharePathsArray = []
                                if (multiSelectActive === true) {
                                    var activeTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                    for (var j = 0; j < activeTimelineModel.count; j++) {
                                        if (activeTimelineModel.get(j).selected === true) {
                                            sharePathsArray.push(activeTimelineModel.get(j).filePath)
                                        }
                                    }
                                }
                                else {
                                    sharePathsArray.push(filePath)
                                }
                                shareAction.resources = sharePathsArray
                                shareAction.trigger()
                            }
                        }
                        MenuItem {
                            enabled: pillowAvailable && multiSelectActive && timelineSelectedTotal > 1
                            visible: enabled
                            text: qsTr("Create animated gif")
                            onClicked: {
                                var gifPathsArray = []
                                var gifAlbumsArray = []
                                var activeTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                for (var j = 0; j < activeTimelineModel.count; j++) {
                                    if (activeTimelineModel.get(j).selected === true) {
                                        gifPathsArray.push(activeTimelineModel.get(j).filePath)
                                        gifAlbumsArray.push(activeTimelineModel.get(j).album)
                                    }
                                }
                                bannerGif.notify( gifPathsArray, decideGifAlbum(gifAlbumsArray) )
                            }
                        }
                        MenuItem {
                            visible: (multiSelectActive === false) || (timelineSelectedTotal > 0)
                            enabled: visible
                            text: qsTr("Delete")
                            onClicked: {
                                var chosenFilesArray = []
                                if (multiSelectActive === true) {
                                    var activeTimelineModel = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered : idListModelImages
                                    for (var j = 0; j < activeTimelineModel.count; j++) {
                                        if (activeTimelineModel.get(j).selected === true) {
                                            chosenFilesArray.push(activeTimelineModel.get(j).filePath)
                                        }
                                    }
                                }
                                else {
                                    chosenFilesArray.push(filePath)
                                }
                                removeFile( chosenFilesArray )
                            }
                        }
                        MenuItem {
                            enabled: multiSelectActive === false
                            visible: enabled
                            text: qsTr("Info")
                            onClicked: {
                                idImageSizeHelper.source = ""
                                idImageSizeHelper.source = filePath
                                var imageWidth = idImageSizeHelper.sourceSize.width
                                var imageHeight = idImageSizeHelper.sourceSize.height
                                py.getEXIFdata( filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite )
                            }
                        }
                        MenuItem {
                            text: (multiSelectActive === true) ? qsTr("Stop selecting") : qsTr("Selection")
                            onClicked: {
                                if (multiSelectActive === true) {
                                    unselectAll()
                                }
                                else {
                                    // start selecting right here, with the long-tapped image already selected
                                    multiSelectActive = true
                                    selected = true
                                    timelineSelectedTotal = timelineSelectedTotal + 1
                                }
                            }
                        }
                    }
                }
                onMenuOpenChanged: {
                    // set variable to disable scrollBar visibility
                    if (menuOpen === true) {
                        delegateMenuOpen = true
                    } else {
                        delegateMenuOpen = false
                    }
                }

                Row {
                    z: -1
                    x: Theme.paddingSmall / 2
                    width: parent.width - x
                    height: parent.height
                    spacing: Theme.paddingLarge

                    Image {
                        id: idImageTimeline
                        width: minimumTimelineListItemHeight - Theme.paddingSmall
                        height: width
                        sourceSize.width: width
                        sourceSize.height: height
                        autoTransform: true
                        fillMode: Image.PreserveAspectCrop
                        source: (reloadImage === false) ? "image://nemoThumbnail/" + filePath : ""
                        asynchronous: true
                        cache: false

                        Rectangle {
                            id: idBackHighlightTimeline
                            visible: selected
                            anchors.fill: parent
                            color: Theme.highlightDimmerColor
                            opacity: 0.5
                        }
                        Icon {
                            id: idIconFavourites
                            visible: isFavourite === "true"
                            highlightColor: Theme.primaryColor
                            width: parent.width / 4.5
                            height: width
                            source: "image://theme/icon-m-favorite-selected?"

                            Rectangle {
                                z: -1
                                anchors.fill: parent
                                visible: isFavourite === "true"
                                color: Theme.highlightDimmerColor
                                opacity: 0.75
                            }
                        }
                    }
                    Column {
                        id: idListRowTimelineDescription
                        width: parent.width - idImageTimeline.width - parent.spacing - Theme.paddingLarge

                        Label {
                            width: parent.width
                            font.pixelSize : Theme.fontSizeTiny
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.Wrap
                            color: Theme.highlightColor
                            text: day + ". " + monthYear
                        }
                        Label {
                            width: parent.width
                            font.pixelSize : Theme.fontSizeTiny
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.Wrap
                            text: (amountDetails === 0) ? (fileName+ " (" + estimatedSize + " MB)") : (filePath+ " (" + estimatedSize + " MB)") //.replace(fileName, "")
                        }
                        Label {
                            width: parent.width
                            font.pixelSize : Theme.fontSizeTiny
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.Wrap
                            text: qsTr("Album: ") + album
                        }
                    }
                }
            }
        }

        SilicaGridView {
            id: idGridViewAlbums
            visible: currentView === "album"
            enabled: visible
            x: idSilicaFlickableFirstPage.width
            width: idSilicaFlickableFirstPage.width
            height: idSilicaFlickableFirstPage.height
            clip: true
            cellWidth: minimumTimelineListItemHeight
            cellHeight: cellWidth
            header: Label {
                width: parent.width
                height: upperFreeHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight //HCenter
                rightPadding: Theme.paddingLarge // * 2
                leftPadding: rightPadding
                color: finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor
                elide: Text.ElideRight
                text: finishedLoading ? (idListModelImages.count) : ((refreshingExifCache ? qsTr("Refreshing EXIF cache") + " " : "") + currentlyScannedImage + "/" + maxScannedImages)
            }
            footer: Item {
                width: parent.width
                height: (isPortrait) ? upperFreeHeight/3 : 0
            }

            PullDownMenu {
                quickSelect: true
                enabled: finishedLoading === true

                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: {
                        // full rescan, same as the timeline and folder views offer
                        clearAllLists()
                        py.scanForImages()
                    }
                }
                MenuItem {
                    text: qsTr("Find duplicates")
                    onClicked: {
                        runDuplicateSearch()
                    }
                }
                MenuItem {
                    text: qsTr("Search")
                    onClicked: {
                        bannerSearch.notify( Theme.highlightDimmerColor )
                    }
                }
            }
            VerticalScrollDecorator {}
            BusyIndicator {
                anchors.centerIn: parent
                running: finishedLoading === false
                size: BusyIndicatorSize.Large
            }

            model: idListModelAlbumTree
            delegate: GridItem {
                enabled: is_filler === false
                contentWidth: minimumTimelineListItemHeight - Theme.paddingSmall
                contentHeight: contentWidth
                contentX: Theme.paddingSmall / 2
                onClicked: {
                    // a group square expands or collapses its sub-albums instead of opening
                    if (is_group === true) {
                        toggleAlbumGroup( album_name )
                        return
                    }
                    if (album_name !== standardSearchAlbum) {
                        var showSearchText = ""
                    }
                    else {
                        showSearchText = tempSearchText
                    }
                    getImagesInAlbum( album_name )
                    multiSelectActive = false
                    pageStack.animatorPush(albumPage, {
                                               showSearchText : showSearchText,
                                               currentModel : "albums"
                                           })
                }

                function clear( album_name, album_count ) {
                    // bugfix: remorse item, because creates width has binding loop
                    remorse.execute( qsTr("Clear Album?"), function() {
                        clearImagesInAlbum( album_name, album_count )
                    })
                }
                function deleteTheseFiles( currentView, currentNameOrFolder, intendedAction ) {
                    // bugfix: remorse item, because creates width has binding loop
                    remorse.execute( qsTr("Delete these files?"), function() {
                        getAllPathsInAlbumOrFolder(currentView, currentNameOrFolder, intendedAction)
                    })
                }

                menu: Component {
                    ContextMenu {
                        hasContent: is_filler === false // groups offer Rename, fillers do nothing
                        onActiveChanged: { // bugfix: stop idCoverImageChangeTimer, otherwise it closes when image changes
                            if (active) { // when menu opened
                                idCoverImageChangeTimer.stop()
                            } else { // when menu closed
                                idCoverImageChangeTimer.start()
                            }
                        }

                        MenuItem {
                            visible: (album_name !== standardAlbum && album_name !== standardSearchAlbum && album_name !== standardFavouritesAlbum && album_name !== standardDuplicatesAlbum )
                            text: qsTr("Rename")
                            onClicked: bannerRename.notify( Theme.highlightDimmerColor, album_name, is_group ) // renaming a group re-prefixes its whole subtree
                        }
                        MenuItem {
                            visible: (album_name !== standardAlbum) && (is_group === false)
                            text: qsTr("Clear")
                            onClicked: clear ( album_name, album_count )
                        }
                        MenuItem {
                            visible: is_group === false
                            text: qsTr("Share as ZIP")
                            onClicked: {
                                getAllPathsInAlbumOrFolder("albums", album_name, "createZip")
                            }
                        }
                        MenuItem {
                            visible: pillowAvailable && (is_group === false)
                            text: qsTr("Resize")
                            onClicked: {
                                getAllPathsInAlbumOrFolder("albums", album_name, "bulkResize")
                            }
                        }
                        MenuItem {
                            visible: is_group === false
                            text: qsTr("Delete")
                            onClicked: {
                                deleteTheseFiles ("albums", album_name, "deleteFiles")
                            }
                        }
                    }
                }

                Rectangle {
                    visible: is_filler === false // filler squares stay empty
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: (album_name !== standardSearchAlbum && album_name !== standardAlbum && album_name !== standardFavouritesAlbum && album_name !== standardDuplicatesAlbum) ? (Theme.rgba(Theme.primaryColor, 0.15)) : (Theme.secondaryHighlightColor) }
                        GradientStop { position: 1; color: Theme.rgba(Theme.primaryColor, 0.02) }
                    }

                    Image {
                        id: idCoverAlbum
                        visible: infoActivateCoverImages !== 0 && finishedLoading
                        anchors.fill: parent
                        width: Theme.iconSizeLarge
                        height: Theme.iconSizeLarge
                        sourceSize.width: width
                        sourceSize.height: height
                        smooth: true
                        asynchronous: true
                        autoTransform: true
                        fillMode: Image.PreserveAspectCrop
                        source: ((random_image !== undefined) && (random_image !== "") ) ? ("image://nemoThumbnail/" + random_image) : ""
                        //onSourceChanged: opacityAlbumImage.start()
                    }
                    Image {
                        visible: infoActivateCoverImages !== 0 && finishedLoading
                        anchors.fill: parent
                        width: Theme.iconSizeLarge
                        height: Theme.iconSizeLarge
                        sourceSize.width: width
                        sourceSize.height: height
                        smooth: true
                        asynchronous: true
                        autoTransform: true
                        fillMode: Image.PreserveAspectCrop
                        source: (previous_image !== "") ? ("image://nemoThumbnail/" + previous_image) : ""
                        NumberAnimation on opacity {
                            id: opacityAlbumImage
                            from: 1
                            to: 0
                            duration: 1000
                        }
                    }
                }
                Label {
                    visible: !idCoverAlbum.visible && is_filler === false
                    anchors.fill: parent
                    anchors.bottomMargin: 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    truncationMode: TruncationMode.Elide
                    font.pixelSize: infoWidthDevider === 2 ? Theme.fontSizeHuge : Theme.fontSizeExtraLarge
                    text: album_count
                }
                Label {
                    visible: !idCoverAlbum.visible && is_filler === false
                    width: parent.width
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: infoWidthDevider === 2 ? (parent.height/6) : (infoWidthDevider === 3 ? parent.height/7 : parent.height/12)
                    truncationMode: TruncationMode.Elide
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: infoWidthDevider === 2 ? Theme.fontSizeSmall : Theme.fontSizeExtraSmall
                    text: display_name
                }
                Label {
                    visible: album_name === standardSearchAlbum && !idCoverAlbum.visible
                    width: parent.width
                    anchors.top: parent.top
                    anchors.topMargin: infoWidthDevider === 2 ? (parent.height/6) : (infoWidthDevider === 3 ? parent.height/7 : parent.height/12)
                    truncationMode: TruncationMode.Elide
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: (infoWidthDevider === 2 ? Theme.fontSizeSmall : Theme.fontSizeExtraSmall)
                    font.italic: true
                    text: tempSearchText
                }
                Label {
                    visible: idCoverAlbum.visible
                    width: parent.width
                    anchors.bottom: parent.bottom
                    truncationMode: TruncationMode.Elide
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: infoWidthDevider === 2 ? Theme.fontSizeMedium : Theme.fontSizeExtraSmall
                    text: display_name + " - " + album_count
                    Rectangle {
                        z: -1
                        visible: idCoverAlbum.visible
                        anchors.centerIn: parent
                        height: parent.paintedHeight
                        width: (parent.width > (parent.paintedWidth+0.6*parent.paintedHeight)) // 0.9
                                ? (parent.paintedWidth + 0.6*parent.paintedHeight)  // 0.9
                                : (parent.width)
                        color: Theme.rgba(Theme.highlightBackgroundColor, 1)
                    }
                }
            }
        }

        SilicaListView {
            id: idListViewFolders
            visible: currentView === "folder"
            enabled: visible
            x: idSilicaFlickableFirstPage.width
            width: idSilicaFlickableFirstPage.width
            height: idSilicaFlickableFirstPage.height
            spacing: Theme.paddingSmall
            clip: true
            header: Label {
                width: parent.width
                height: upperFreeHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight //HCenter
                rightPadding: Theme.paddingLarge // * 2
                leftPadding: rightPadding
                color: finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor
                text: finishedLoading ? (idListModelImages.count + " | " + idListModelFolders.count) : ((refreshingExifCache ? qsTr("Refreshing EXIF cache") + " " : "") + currentlyScannedImage + "/" + maxScannedImages)
            }
            footer: Item {
                width: parent.width
                height: (isPortrait) ? upperFreeHeight/3 : 0
            }

            PullDownMenu {
                quickSelect: true
                enabled: finishedLoading === true

                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: {
                        // full rescan, picks up images that arrived outside the app and re-counts albums and folders
                        clearAllLists()
                        py.scanForImages()
                    }
                }
                MenuItem {
                    enabled: fileBrowserInstalled
                    text: (fileBrowserInstalled) ? qsTr("File Browser") : qsTr("File Browser not installed")
                    onClicked: {
                        py.runCMDtool("harbour-file-browser")
                    }
                }
                MenuItem {
                    text: qsTr("About")
                    onClicked:  {
                        pageStack.animatorPush(Qt.resolvedUrl("AboutPage.qml"), {})
                    }
                }
            }
            VerticalScrollDecorator {}
            BusyIndicator {
                anchors.centerIn: parent
                running: finishedLoading === false
                size: BusyIndicatorSize.Large
            }

            model: idListModelFolders
            delegate: ListItem {
                width: parent.width
                contentHeight: Math.max( idListRowDescription.height, minimumFolderListItemHeight )
                onClicked: {
                    var showSearchText = ""
                    getImagesInFolder( folder_name )
                    pageStack.animatorPush(albumPage, {
                                               showSearchText : showSearchText,
                                               currentModel : "folders"
                                           })
                }
                function deleteTheseFiles( currentView, currentNameOrFolder, intendedAction ) {
                    remorseAction( qsTr("Delete these files?"), function() {
                        getAllPathsInAlbumOrFolder(currentView, currentNameOrFolder, intendedAction)
                    })
                }
                menu: Component {
                    ContextMenu {
                        MenuItem {
                            text: qsTr("Set Album")
                            onClicked: {
                                var chosenFilesArray = []
                                getImagesInFolder( folder_name )
                                for (var j = 0; j < idListModelImagesFolder.count; j++) {
                                    var targetIndex_FolderOrAlbum = j
                                    chosenFilesArray.push( [targetIndex_FolderOrAlbum, idListModelImagesFolder.get(j).filePath, idListModelImagesFolder.get(j).listModelImages_baseIndex] )
                                }
                                bannerToAlbum.notify( Theme.highlightDimmerColor, Theme.itemSizeHuge, chosenFilesArray, "fromFolder", "triggeredOnFirstPage" )
                            }
                        }
                        MenuItem {
                            text: qsTr("Share as ZIP")
                            onClicked: {
                                getAllPathsInAlbumOrFolder("folders", folder_name, "createZip")
                            }
                        }
                        MenuItem {
                            visible: pillowAvailable
                            text: qsTr("Resize")
                            onClicked: {
                                getAllPathsInAlbumOrFolder("folders", folder_name, "bulkResize")
                            }
                        }
                        MenuItem {
                            text: qsTr("Delete")
                            onClicked: {
                                deleteTheseFiles ("folders", folder_name, "deleteFiles")
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: parent.height

                    Label {
                        id: idLabelAmountImagesFolder
                        visible: idCoverFolder.visible
                        width: parent.width / 7
                        rightPadding: Theme.paddingLarge
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize : infoWidthDevider === 2 ? Theme.fontSizeLarge : Theme.fontSizeMedium
                        color: Theme.secondaryColor
                        text: folder_count
                    }
                    Rectangle {
                        id: idListRowFolder
                        width: minimumFolderListItemHeight
                        height: Math.max( idListRowDescription.height, minimumFolderListItemHeight )
                        gradient: Gradient {
                                GradientStop { position: 0.0; color: Theme.rgba(Theme.primaryColor, 0.15) }
                                GradientStop { position: 1; color: Theme.rgba(Theme.primaryColor, 0.02) }
                        }

                        Image {
                            id: idCoverFolder
                            visible: infoActivateCoverImages !== 0 && finishedLoading
                            anchors.fill: parent
                            width: Theme.iconSizeLarge
                            height: Theme.iconSizeLarge
                            sourceSize.width: width
                            sourceSize.height: height
                            smooth: true
                            autoTransform: true
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: ((random_image !== undefined) && (random_image !== "") ) ? ("image://nemoThumbnail/" + random_image) : ""
                            onSourceChanged: opacityFolderImage.start()
                        }
                        Image {
                            visible: infoActivateCoverImages !== 0 && finishedLoading
                            anchors.fill: parent
                            width: Theme.iconSizeLarge
                            height: Theme.iconSizeLarge
                            sourceSize.width: width
                            sourceSize.height: height
                            smooth: true
                            autoTransform: true
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            onOpacityChanged:
                                if (opacity === 0) {
                                    source = idCoverFolder.source
                                    opacity = 1
                                }
                            NumberAnimation on opacity {
                                id: opacityFolderImage
                                from: 1
                                to: 0
                                duration: 1000
                            }
                        }
                        Label {
                            visible: !idCoverFolder.visible
                            height: parent.height
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            truncationMode: TruncationMode.Elide
                            font.pixelSize: infoWidthDevider === 2 ? Theme.fontSizeLarge : Theme.fontSizeMedium //Theme.fontSizeMedium
                            text: folder_count
                        }
                    }
                    Label {
                        id: idListRowDescription
                        width: (idCoverFolder.visible) ? (parent.width - idLabelAmountImagesFolder.width - idListRowFolder.width) : (parent.width - idListRowFolder.width)
                        leftPadding: Theme.paddingLarge
                        rightPadding: leftPadding //* 2
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize : Theme.fontSizeTiny
                        wrapMode: Text.Wrap
                        text: folder_name
                    }
                }
            }
        }
    }

    // the bar sits inside its own flickable, so the timeline pull-up menu can be dragged open from the bar at any scroll position
    SilicaFlickable {
        id: idBottomMenuFlickable
        y: appHeight - height
        width: page.width
        height: Theme.itemSizeMedium
        contentHeight: height
        flickableDirection: Flickable.VerticalFlick
        clip: true

        PushUpMenu {
            id: idPushUpMenu
            visible: (currentView === "timeline")
            enabled: (finishedLoading === true) && visible
            quickSelect: true
            highlightColor: (multiSelectActive === false) ? Theme.highlightBackgroundColor : Theme.errorColor
            backgroundColor: (multiSelectActive === false) ? Theme.highlightBackgroundColor : Theme.errorColor
            // the margin is functional: the lowermost item only stays highlighted for release-to-select while the drag sits
            // between the content end and the final position, and the margin is exactly that headroom - with 0 every full
            // pull lands on the final position where silica drops the highlight and locks the menu open until tapped.
            // half the default (Theme.itemSizeSmall) keeps the release zone but halves the empty space below the last item
            bottomMargin: Theme.itemSizeSmall / 2

            MenuItem {
                text: (multiSelectActive === true) ? qsTr("Unselect") : qsTr("Selection")
                onClicked: {
                    if (multiSelectActive === true) {
                        unselectAll()
                    }
                    else {
                        multiSelectActive = true
                    }
                }
            }
            MenuItem {
                text: (timelineAlbumFilter !== "") ? qsTr("Show all") : qsTr("Filter by album")
                onClicked: {
                    if (timelineAlbumFilter !== "") {
                        clearTimelineAlbumFilter()
                    }
                    else {
                        bannerToAlbum.notify( Theme.highlightDimmerColor, Theme.itemSizeHuge, [], "fromTimeline", "triggeredOnFirstPage", true )
                    }
                }
            }
            MenuItem {
                text: (timelineSortDirection === "0") ? qsTr("Show oldest first") : qsTr("Show newest first")
                onClicked: {
                    reverseTimelineOrder()
                }
            }
        }

        Rectangle {
        id: idFooterRow
        width: page.width
        height: Theme.itemSizeMedium
        color: Theme.highlightDimmerColor

        Row {
            anchors.fill: parent

            Label {
                width: parent.width / 7 * 2
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeLarge
                color: (currentView === "timeline") ? (finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor) : (finishedLoading ? Theme.primaryColor : Theme.secondaryColor)
                text: qsTr("Timeline")

                MouseArea {
                    enabled: finishedLoading
                    anchors.fill: parent
                    onClicked: {
                        currentView = "timeline"
                        storageItem.setSetting("infoCurrentView", "timeline")
                    }
                }
            }
            Label {
                width: parent.width / 7* 2
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeLarge
                color: (currentView === "album") ? (finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor) : (finishedLoading ? Theme.primaryColor : Theme.secondaryColor)
                text: qsTr("Album")

                MouseArea {
                    enabled: finishedLoading
                    anchors.fill: parent
                    onClicked: {
                        currentView = "album"
                        storageItem.setSetting("infoCurrentView", "album")
                    }
                }
            }
            Label {
                width: parent.width / 7* 2
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeLarge
                color: (currentView === "folder") ? (finishedLoading ? Theme.highlightColor : Theme.secondaryHighlightColor) : (finishedLoading ? Theme.primaryColor : Theme.secondaryColor)
                text: qsTr("Folder")

                MouseArea {
                    enabled: finishedLoading
                    anchors.fill: parent
                    onClicked: {
                        currentView = "folder"
                        storageItem.setSetting("infoCurrentView", "folder")
                    }
                }
            }
            IconButton {
                enabled: finishedLoading
                width: parent.width / 7
                height: parent.height
                icon.scale: 0.9
                icon.color: Theme.primaryColor
                icon.source: "image://theme/icon-m-developer-mode?"
                onClicked: {
                    pageStack.animatorPush(Qt.resolvedUrl("SettingsPage.qml"), {
                        standardScreenHeight : standardScreenHeight,
                        amountExtPartitions : amountExtPartitions,
                    })
                }
                onPressAndHold: {
                    rumbleEffect.start()
                    clearAllLists()
                    py.scanForImages()
                    py.checkDB_fileExistance()
                }
            }
        }
        }
    }

    // necessary functions
    function randomIntFromInterval(min, max) { // min and max included
      return Math.floor(Math.random() * (max - min + 1) + min)
    }

    function clearAllLists() {
        idListModelImages.clear()
        idListModelImagesAlbum.clear()
        idListModelAlbums.clear()
        idListModelFolders.clear()
        idListModelImagesFolder.clear()
        idListModelSearch.clear()
        idListModelFavourites.clear()
        idListModelTimelineFiltered.clear()
        // idListModelDuplicates is kept: the results are not derivable from a rescan, stale rows get pruned and re-mapped afterwards
        timelineAlbumFilter = ""
    }

    function countDistinctAlbums() {
        // clear listmodel and re-create it with new values
        idListModelAlbums.clear()
        // collect all albums and their files in a single pass instead of re-scanning the image model per album
        var albumFilesMap = ({})
        for (var i = 0; i < idListModelImages.count; i++) {
            var imageItem = idListModelImages.get(i)
            if (albumFilesMap[imageItem.album] === undefined) {
                albumFilesMap[imageItem.album] = []
            }
            albumFilesMap[imageItem.album].push( imageItem.filePath )
        }
        distinctAlbums = Object.keys(albumFilesMap)
        if (idListModelSearch.count > 0) {
            distinctAlbums.push( standardSearchAlbum ) // visible when there are search results
        }
        if (idListModelFavourites.count > 0) {
            distinctAlbums.push( standardFavouritesAlbum ) // visible when there are favorites
        }
        if (idListModelDuplicates.count > 0) {
            distinctAlbums.push( standardDuplicatesAlbum ) // visible when duplicates were searched and found
        }
        distinctAlbums = distinctAlbums.sort()

        // count items and assign a random image
        for (var j = 0; j < distinctAlbums.length; j++) {
            var counter = 0
            var randomIndex
            var randomFilePath = ""

            // search album
            if (distinctAlbums[j] === standardSearchAlbum) {
                counter = idListModelSearch.count
                if (counter > 0 && infoActivateCoverImages) {
                    randomIndex = randomIntFromInterval(0, counter-1)
                    randomFilePath = idListModelSearch.get(randomIndex).filePath
                }
            }
            // favourites album
            else if (distinctAlbums[j] === standardFavouritesAlbum) {
                counter = idListModelFavourites.count
                if (counter > 0 && infoActivateCoverImages) {
                    randomIndex = randomIntFromInterval(0, counter-1)
                    randomFilePath = idListModelFavourites.get(randomIndex).filePath
                }
            }
            // duplicates album
            else if (distinctAlbums[j] === standardDuplicatesAlbum) {
                counter = idListModelDuplicates.count
                if (counter > 0 && infoActivateCoverImages) {
                    randomIndex = randomIntFromInterval(0, counter-1)
                    randomFilePath = idListModelDuplicates.get(randomIndex).filePath
                }
            }
            // other albums
            else {
                counter = albumFilesMap[distinctAlbums[j]].length
                if (infoActivateCoverImages) {
                    randomIndex = randomIntFromInterval(0, counter-1)
                    randomFilePath = albumFilesMap[distinctAlbums[j]][randomIndex]
                }
            }

            // now add to album listmodel
            idListModelAlbums.append({ "album_name" : distinctAlbums[j],
            //idListModelAlbums.set(j,{ "album_name" : distinctAlbums[j],
                                       "album_count" : counter,
                                       "random_image" : randomFilePath,
                                       "previous_image" : (previousRandomImagesAlbumArray[j] !== undefined) ? previousRandomImagesAlbumArray[j] : ""
                                     })
            // store that info in an array as well which we can use next time
            previousRandomImagesAlbumArray[j] = randomFilePath
        }
        //console.log(previousRandomImagesAlbumArray)

        buildAlbumTree()
    }

    function toggleAlbumGroup( groupPrefix ) {
        if (expandedAlbumPrefixes[groupPrefix] === true) {
            delete expandedAlbumPrefixes[groupPrefix]
        }
        else {
            expandedAlbumPrefixes[groupPrefix] = true
        }
        buildAlbumTree()
    }

    function buildAlbumTree() {
        // coalesce the flat album list into a tree by the "Foo / Bar / Baz" naming convention:
        // one square per first component with the aggregated count, expanding on tap into its sub-albums
        var nodeByPrefix = ({})
        var prefixList = []
        for (var i = 0; i < idListModelAlbums.count; i++) {
            var fullName = idListModelAlbums.get(i).album_name
            var isSpecialAlbum = (fullName === standardAlbum || fullName === standardSearchAlbum || fullName === standardFavouritesAlbum || fullName === standardDuplicatesAlbum)
            var nameParts = isSpecialAlbum ? [fullName] : fullName.split(" / ")
            var prefix = ""
            for (var p = 0; p < nameParts.length; p++) {
                var parentPrefix = prefix
                prefix = (p === 0) ? nameParts[p] : prefix + " / " + nameParts[p]
                if (nodeByPrefix[prefix] === undefined) {
                    nodeByPrefix[prefix] = { "displayName" : (isSpecialAlbum ? nameParts[p].substring(1) : nameParts[p]), "parentPrefix" : parentPrefix, "depth" : p,
                                             "count" : 0, "image" : "", "ownCount" : 0, "ownImage" : "", "previousImage" : "", "isAlbum" : false, "hasChildren" : false }
                    prefixList.push(prefix)
                }
                nodeByPrefix[prefix].count += idListModelAlbums.get(i).album_count
                if (nodeByPrefix[prefix].image === "") { nodeByPrefix[prefix].image = idListModelAlbums.get(i).random_image }
                if (p === nameParts.length - 1) {
                    nodeByPrefix[prefix].isAlbum = true
                    nodeByPrefix[prefix].ownCount = idListModelAlbums.get(i).album_count
                    nodeByPrefix[prefix].ownImage = idListModelAlbums.get(i).random_image
                    nodeByPrefix[prefix].previousImage = idListModelAlbums.get(i).previous_image
                }
                else {
                    nodeByPrefix[prefix].hasChildren = true
                }
            }
        }

        prefixList.sort() // keeps children right after their group since " " sorts before any letter
        idListModelAlbumTree.clear()
        var columnsPerRow = Math.max(1, Math.floor(idGridViewAlbums.width / idGridViewAlbums.cellWidth))
        var lastEmittedDepth = -1
        for (i = 0; i < prefixList.length; i++) {
            var node = nodeByPrefix[prefixList[i]]

            // a row is visible only while every ancestor group is expanded
            var visibleRow = true
            var ancestorPrefix = node.parentPrefix
            while (ancestorPrefix !== "") {
                if (expandedAlbumPrefixes[ancestorPrefix] !== true) { visibleRow = false }
                ancestorPrefix = nodeByPrefix[ancestorPrefix].parentPrefix
            }

            if (visibleRow === true) {
                // every change of tree depth starts a fresh grid row, sub-albums always sit on their own rows
                if (lastEmittedDepth !== -1 && node.depth !== lastEmittedDepth) {
                    padAlbumTreeRow(columnsPerRow)
                }
                var expandMarker = (node.hasChildren === true) ? ((expandedAlbumPrefixes[prefixList[i]] === true) ? "▼ " : "▶ ") : ""
                idListModelAlbumTree.append({ "album_name" : prefixList[i],
                                              "display_name" : expandMarker + ((node.depth === 0) ? node.displayName : prefixList[i]),
                                              "album_count" : node.count,
                                              "random_image" : node.image,
                                              "previous_image" : (node.hasChildren === true) ? "" : node.previousImage,
                                              "is_group" : node.hasChildren,
                                              "depth" : node.depth,
                                              "is_filler" : false
                                            })
                lastEmittedDepth = node.depth
                // an album that also has sub-albums gets an own leaf row when expanded, holding just its own images
                if (node.hasChildren === true && node.isAlbum === true && expandedAlbumPrefixes[prefixList[i]] === true) {
                    padAlbumTreeRow(columnsPerRow)
                    idListModelAlbumTree.append({ "album_name" : prefixList[i],
                                                  "display_name" : prefixList[i],
                                                  "album_count" : node.ownCount,
                                                  "random_image" : node.ownImage,
                                                  "previous_image" : node.previousImage,
                                                  "is_group" : false,
                                                  "depth" : node.depth + 1,
                                                  "is_filler" : false
                                                })
                    lastEmittedDepth = node.depth + 1
                }
            }
        }
    }

    function padAlbumTreeRow( columnsPerRow ) {
        // textless disabled squares filling the rest of a grid row
        while (idListModelAlbumTree.count % columnsPerRow !== 0) {
            idListModelAlbumTree.append({ "album_name" : "", "display_name" : "", "album_count" : 0,
                                          "random_image" : "", "previous_image" : "", "is_group" : false,
                                          "depth" : 0, "is_filler" : true })
        }
    }

    function countDistinctFolders() {
        idListModelFolders.clear() // creates trouble, sometimes scrolls list back up to zero on randomizing ... how to avoid that???

        // collect all folders and their files in a single pass, growing the listmodel strings per image is far too slow
        var uniqueFoldersArray = []
        var folderFilesMap = ({})
        for (var i = 0; i < idListModelImages.count; i++) {
            var imageItem = idListModelImages.get(i)
            if (folderFilesMap[imageItem.folderPath] === undefined) {
                uniqueFoldersArray.push( imageItem.folderPath )
                folderFilesMap[imageItem.folderPath] = []
            }
            folderFilesMap[imageItem.folderPath].push( imageItem.filePath )
        }
        for (var j = 0; j < uniqueFoldersArray.length; j++) {
            idListModelFolders.append({ "folder_name" : uniqueFoldersArray[j],
                                        "folder_count" : folderFilesMap[uniqueFoldersArray[j]].length,
                                        "folder_files_all" : (folderFilesMap[uniqueFoldersArray[j]]).join("|||"),
                                        "random_image" : "",
                                      })
        }
        // now sort listmodel alphabetically and cleanup
        idListModelFolders.quick_sort()
        uniqueFoldersArray = []
        folderFilesMap = ({})
    }

    function randomizeDistinctFoldersArray() {
        if (infoActivateCoverImages) {
            for (var i = 0; i < idListModelFolders.count; i++) {
                var allFilesInFolderArray = ( idListModelFolders.get(i).folder_files_all ).split("|||")
                var randomIndex = randomIntFromInterval(0, allFilesInFolderArray.length-1)
                var randomFilePath = allFilesInFolderArray[randomIndex]
                //console.log(randomFilePath)
                idListModelFolders.setProperty( i, "random_image", randomFilePath)
            }
        }
    }

    function getImagesInAlbum( albumName ) {
        currentAlbum = albumName
        idListModelImagesAlbum.clear()

        if (albumName !== standardSearchAlbum && albumName !== standardFavouritesAlbum && albumName !== standardDuplicatesAlbum) {
            for (var i = 0; i < idListModelImages.count; i++) {
                if ( (idListModelImages.get(i).album) === albumName ) {
                    idListModelImagesAlbum.append({
                        "creationDateMS" : idListModelImages.get(i).creationDateMS,
                        "filePath" : idListModelImages.get(i).filePath,
                        "monthYear" : idListModelImages.get(i).monthYear,
                        "day" : idListModelImages.get(i).day,
                        "folderPath" : idListModelImages.get(i).folderPath,
                        "fileName" : idListModelImages.get(i).fileName,
                        "estimatedSize" : idListModelImages.get(i).estimatedSize,
                        "album" : idListModelImages.get(i).album,
                        "selected" : false,
                        "exifInfo" :  idListModelImages.get(i).album,
                        "isSearchResult" : false,
                        "timestampSource" : idListModelImages.get(i).timestampSource,
                        "isFavourite" : idListModelImages.get(i).isFavourite,
                        "listModelImages_baseIndex" : i
                    })
                }
            }
        }

        else if (albumName === standardDuplicatesAlbum) {
            for (i = 0; i < idListModelDuplicates.count; i++) {
                idListModelImagesAlbum.append({
                    "creationDateMS" : idListModelDuplicates.get(i).creationDateMS,
                    "filePath" : idListModelDuplicates.get(i).filePath,
                    "monthYear" : idListModelDuplicates.get(i).monthYear,
                    "day" : idListModelDuplicates.get(i).day,
                    "folderPath" : idListModelDuplicates.get(i).folderPath,
                    "fileName" : idListModelDuplicates.get(i).fileName,
                    "estimatedSize" : idListModelDuplicates.get(i).estimatedSize,
                    "album" : idListModelDuplicates.get(i).album,
                    "selected" : false,
                    "exifInfo" :  idListModelDuplicates.get(i).album,
                    "isSearchResult" : false,
                    "timestampSource" : idListModelDuplicates.get(i).timestampSource,
                    "isFavourite" : idListModelDuplicates.get(i).isFavourite,
                    "listModelImages_baseIndex" : idListModelDuplicates.get(i).listModelImages_baseIndex
                })
            }
        }

        else if (albumName === standardFavouritesAlbum) {
            //console.log("favourites")
            for (i = 0; i < idListModelFavourites.count; i++) {
                idListModelImagesAlbum.append({
                    "creationDateMS" : idListModelFavourites.get(i).creationDateMS,
                    "filePath" : idListModelFavourites.get(i).filePath,
                    "monthYear" : idListModelFavourites.get(i).monthYear,
                    "day" : idListModelFavourites.get(i).day,
                    "folderPath" : idListModelFavourites.get(i).folderPath,
                    "fileName" : idListModelFavourites.get(i).fileName,
                    "estimatedSize" : idListModelFavourites.get(i).estimatedSize,
                    "album" : idListModelFavourites.get(i).album,
                    "selected" : false,
                    "exifInfo" :  idListModelFavourites.get(i).album,
                    "isSearchResult" : false,
                    "timestampSource" : idListModelFavourites.get(i).timestampSource,
                    "isFavourite" : idListModelFavourites.get(i).isFavourite,
                    "listModelImages_baseIndex" : idListModelFavourites.get(i).listModelImages_baseIndex
                })
            }
        }

        else { // must be search results then
            //console.log("search")
            for (i = 0; i < idListModelSearch.count; i++) {
                idListModelImagesAlbum.append({
                    "creationDateMS" : idListModelSearch.get(i).creationDateMS,
                    "filePath" : idListModelSearch.get(i).filePath,
                    "monthYear" : idListModelSearch.get(i).monthYear,
                    "day" : idListModelSearch.get(i).day,
                    "folderPath" : idListModelSearch.get(i).folderPath,
                    "fileName" : idListModelSearch.get(i).fileName,
                    "estimatedSize" : idListModelSearch.get(i).estimatedSize,
                    "album" : idListModelSearch.get(i).album,
                    "selected" : false,
                    "exifInfo" :  idListModelSearch.get(i).album,
                    "isSearchResult" : idListModelSearch.get(i).isSearchResult,
                    "timestampSource" : idListModelSearch.get(i).timestampSource,
                    "isFavourite" : idListModelSearch.get(i).isFavourite,
                    "listModelImages_baseIndex" : idListModelSearch.get(i).listModelImages_baseIndex
                })
            }
        }
    }

    function clearImagesInAlbum ( albumName, albumCount ) {

        // search album
        if (albumName === standardSearchAlbum) {
            idListModelSearch.clear()
        }

        // duplicates album
        else if (albumName === standardDuplicatesAlbum) {
            idListModelDuplicates.clear()
        }

        // favourites album
        else if (albumName === standardFavouritesAlbum) {
            idListModelFavourites.clear()

            // update main image list
            for (var i = 0; i < idListModelImages.count; i++) {
                if (idListModelImages.get(i).isFavourite !== "false") {
                    idListModelImages.setProperty(i, "isFavourite", "false")
                    storageItem.removeKeywords(idListModelImages.get(i).filePath)
                }
            }

            // update current album list
            for (var l = 0; l < idListModelImagesAlbum.count; l++) {
                if (idListModelImagesAlbum.get(l).isFavourite !== "false") {
                    idListModelImagesAlbum.setProperty(l, "isFavourite", "false")
                }
            }

            // update current folder list
            for (l = 0; l < idListModelImagesFolder.count; l++) {
                if (idListModelImagesFolder.get(l).isFavourite !== "false") {
                    idListModelImagesFolder.setProperty(l, "isFavourite", "false")
                }
            }

            // possibly update search results list as well
            for (l = 0; l < idListModelSearch.count; l++) {
                if (idListModelSearch.get(l).isFavourite !== "false") {
                    idListModelSearch.setProperty(l, "isFavourite", "false")
                }
            }

        }

        // all user albums
        else {
            // remove all album entry by resetting Album to default value "UNSORTED", also update DB
            for (var k = 0; k < idListModelImages.count; k++) {
                if (idListModelImages.get(k).album === albumName) {
                    idListModelImages.setProperty(k, "album", standardAlbum)
                    storageItem.removeAlbum(idListModelImages.get(k).filePath)
                    // also remove IPTC keywords if available
                    if (settingUseExif !== 0) {
                        py.removeMetadataKeywords(idListModelImages.get(k).filePath)
                    }
                }
            }

            // update favouritesModel as well
            if (idListModelFavourites.count > 0) {
                for ( k = 0; k < idListModelFavourites.count; k++) {
                    if (idListModelFavourites.get(k).album === albumName) {
                        idListModelFavourites.setProperty(k, "album", standardAlbum)
                    }
                }
            }

            // update searchModel as well
            if (idListModelSearch.count > 0) {
                for ( k = 0; k < idListModelSearch.count; k++) {
                    if (idListModelSearch.get(k).album === albumName) {
                        idListModelSearch.setProperty(k, "album", standardAlbum)
                    }
                }
            }

            // finally remove album from distinct album list when empty
            for (var j = idListModelAlbums.count -1; j >= 0; --j) {
                if (idListModelAlbums.get(j).album_name === albumName) {
                    idListModelAlbums.remove(j)
                }
            }
        }

        // start new counting of albums
        if (idListModelSearch.count < 1) {
            countDistinctAlbums( "standard" )
        }
        else {
                countDistinctAlbums( "fromSearch" )
            }
    }

    function getImagesInFolder( folderName ) {
        currentFolder = folderName
        currentFolderAlbumFilter = "" // opening a folder always starts unfiltered
        idListModelImagesFolder.clear()

        for (var i = 0; i < idListModelImages.count; i++) {
            if ( (idListModelImages.get(i).folderPath) === folderName ) {
                idListModelImagesFolder.append({
                    "creationDateMS" : idListModelImages.get(i).creationDateMS,
                    "filePath" : idListModelImages.get(i).filePath,
                    "monthYear" : idListModelImages.get(i).monthYear,
                    "day" : idListModelImages.get(i).day,
                    "folderPath" : idListModelImages.get(i).folderPath,
                    "fileName" : idListModelImages.get(i).fileName,
                    "estimatedSize" : idListModelImages.get(i).estimatedSize,
                    "album" : idListModelImages.get(i).album,
                    "selected" : false,
                    "exifInfo" :  idListModelImages.get(i).album,
                    "isSearchResult" : false,
                    "timestampSource" : idListModelImages.get(i).timestampSource,
                    "isFavourite" : idListModelImages.get(i).isFavourite,
                    "listModelImages_baseIndex" : i
                })
            }
        }
    }

    function dropLonelyDuplicateGroups() {
        // a group whose partners got deleted, renamed away or dropped out of the scan must not
        // linger as a single image - being alone in DUPLICATES means nothing was duplicated
        var membersPerGroup = ({})
        for (var i = 0; i < idListModelDuplicates.count; i++) {
            var groupNumber = idListModelDuplicates.get(i).duplicateGroup
            membersPerGroup[groupNumber] = (membersPerGroup[groupNumber] === undefined) ? 1 : membersPerGroup[groupNumber] + 1
        }
        var droppedAny = false
        for (i = idListModelDuplicates.count -1; i >= 0; --i) {
            if (membersPerGroup[idListModelDuplicates.get(i).duplicateGroup] < 2) {
                idListModelDuplicates.remove(i)
                droppedAny = true
            }
        }
        // the survivor was not deleted, so nothing else would take its copy out of an open duplicates page
        if (droppedAny === true && currentAlbum === standardDuplicatesAlbum) {
            getImagesInAlbum( standardDuplicatesAlbum )
        }
    }

    function remapBaseIndexes() {
        // re-map the stored positions into idListModelImages after its rows shifted
        var pathIndexMap = ({})
        for (var i = 0; i < idListModelImages.count; i++) {
            pathIndexMap[idListModelImages.get(i).filePath] = i
        }
        for (var l = 0; l < idListModelFavourites.count; l++) {
            idListModelFavourites.setProperty(l, "listModelImages_baseIndex", pathIndexMap[idListModelFavourites.get(l).filePath])
        }
        for (l = 0; l < idListModelTimelineFiltered.count; l++) {
            if (pathIndexMap[idListModelTimelineFiltered.get(l).filePath] !== undefined) {
                idListModelTimelineFiltered.setProperty(l, "listModelImages_baseIndex", pathIndexMap[idListModelTimelineFiltered.get(l).filePath])
            }
        }
        // the duplicates results outlive rescans, rows of vanished files get dropped here
        for (l = idListModelDuplicates.count -1; l >= 0; --l) {
            if (pathIndexMap[idListModelDuplicates.get(l).filePath] === undefined) {
                idListModelDuplicates.remove(l)
            }
            else {
                idListModelDuplicates.setProperty(l, "listModelImages_baseIndex", pathIndexMap[idListModelDuplicates.get(l).filePath])
            }
        }
        for (var k = 0; k < idListModelImagesAlbum.count; k++) {
            if (pathIndexMap[idListModelImagesAlbum.get(k).filePath] !== undefined) {
                idListModelImagesAlbum.setProperty(k, "listModelImages_baseIndex", pathIndexMap[idListModelImagesAlbum.get(k).filePath])
            }
        }
        for (var o = 0; o < idListModelImagesFolder.count; o++) {
            if (pathIndexMap[idListModelImagesFolder.get(o).filePath] !== undefined) {
                idListModelImagesFolder.setProperty(o, "listModelImages_baseIndex", pathIndexMap[idListModelImagesFolder.get(o).filePath])
            }
        }

        dropLonelyDuplicateGroups() // pruning above may have left a group with a single member
    }

    function runDuplicateSearch() {
        // hashing every image takes a while on the first run, later runs reuse the cached hashes
        var allPathsArray = []
        for (var i = 0; i < idListModelImages.count; i++) {
            allPathsArray.push(idListModelImages.get(i).filePath)
        }
        finishedLoading = false
        py.findDuplicateImages( allPathsArray, (infoDuplicateTolerance === 0) ? 0 : 4 )
    }

    property var trackedDuplicateTolerance : infoDuplicateTolerance // watchdog pattern: a changed matching setting rebuilds existing results
    onTrackedDuplicateToleranceChanged: {
        if (idListModelDuplicates.count > 0) {
            runDuplicateSearch()
        }
    }

    function decideGifAlbum( albumsArray ) {
        // all frames in one album -> the gif joins it, UNSORTED entries do not break the deal
        var targetAlbum = ""
        for (var i = 0; i < albumsArray.length; i++) {
            if (albumsArray[i] !== standardAlbum) {
                if (targetAlbum === "") {
                    targetAlbum = albumsArray[i]
                }
                else if (targetAlbum !== albumsArray[i]) {
                    return ""
                }
            }
        }
        return targetAlbum
    }

    function showImageInTimeline( targetPath ) {
        // jump to the full timeline and center the image, eg. after tapping the gif-created notification.
        // the timeline lives on this page - a pushed album/folder/viewer page would hide the jump completely
        var popGuard = 0
        while (pageStack.depth > 1 && popGuard < 10) {
            pageStack.pop(undefined, PageStackAction.Immediate)
            popGuard += 1
        }
        currentView = "timeline"
        storageItem.setSetting("infoCurrentView", "timeline")
        timelineAlbumFilter = ""
        idListModelTimelineFiltered.clear()
        var foundIndex = -1
        for (var i = 0; i < idListModelImages.count; i++) {
            if (idListModelImages.get(i).filePath === targetPath) {
                foundIndex = i
            }
        }
        if (foundIndex >= 0) {
            pendingTimelineJumpPath = ""
            idListViewTimeline.positionViewAtIndex( foundIndex, ListView.Center ) // the viewer pops back onto the right spot
            // and open the image itself, exactly like tapping it in the timeline
            var allCurrentModelImagePathsArray = []
            for (i = 0; i < idListModelImages.count; i++) {
                allCurrentModelImagePathsArray.push(idListModelImages.get(i).filePath)
            }
            pageStack.animatorPush(viewPage, {
                                       upperFreeHeight : upperFreeHeight,
                                       allCurrentModelImagePathsArray : allCurrentModelImagePathsArray,
                                       currentImageIndex : foundIndex,
                                   })
        }
        else {
            pendingTimelineJumpPath = targetPath // probably still being scanned in, retried when the scan lands
        }
    }

    function switchViewBySwipe( direction ) {
        if (finishedLoading === false) { return }
        var viewOrder = ["timeline", "album", "folder"]
        var viewIndex = viewOrder.indexOf(currentView) + direction
        if (viewIndex < 0 || viewIndex >= viewOrder.length) { return } // no wrap around, settings only opens by tapping its button
        currentView = viewOrder[viewIndex]
        storageItem.setSetting("infoCurrentView", currentView)
    }

    function centeredTimelineIndex() {
        // index of the image currently centered on screen, the center may hit a section header or the row spacing so probe around it
        var centeredIndex = idListViewTimeline.indexAt( idListViewTimeline.width / 2, idListViewTimeline.contentY + idListViewTimeline.height / 2 )
        if (centeredIndex < 0) {
            centeredIndex = idListViewTimeline.indexAt( idListViewTimeline.width / 2, idListViewTimeline.contentY + idListViewTimeline.height / 2 + minimumTimelineListItemHeight / 2 )
        }
        if (centeredIndex < 0) {
            centeredIndex = idListViewTimeline.indexAt( idListViewTimeline.width / 2, idListViewTimeline.contentY + idListViewTimeline.height / 2 - minimumTimelineListItemHeight / 2 )
        }
        return centeredIndex
    }

    function clearTimelineAlbumFilter() {
        if (multiSelectActive === true) { unselectAll() } // the selection flags of the rebuilt rows would go stale
        // keep the centered image centered when going back to the full list, its position there is the stored base index
        var centeredIndex = centeredTimelineIndex()
        var mainListIndex = (centeredIndex >= 0) ? idListModelTimelineFiltered.get(centeredIndex).listModelImages_baseIndex : -1
        timelineAlbumFilter = ""
        idListModelTimelineFiltered.clear()
        if (mainListIndex >= 0) {
            idListViewTimeline.positionViewAtIndex( mainListIndex, ListView.Center )
        }
    }

    function reverseTimelineOrder() {
        // remember what is centered on screen right now, the reversal must keep it there
        var visibleModelCount = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered.count : idListModelImages.count
        var centeredIndex = centeredTimelineIndex()

        // flip the stored direction so the next scan sorts the same way
        timelineSortDirection = (timelineSortDirection === "0") ? "1" : "0"
        storageItem.setSetting( "infoTimeLineDirectionIndex", timelineSortDirection )

        // rebuild the lists in reverse, much faster than a full rescan
        var reversedRowsArray = []
        for (var i = idListModelImages.count -1; i >= 0; --i) {
            var imageItem = idListModelImages.get(i)
            reversedRowsArray.push({
                "creationDateMS" : imageItem.creationDateMS,
                "filePath" : imageItem.filePath,
                "monthYear" : imageItem.monthYear,
                "day" : imageItem.day,
                "folderPath" : imageItem.folderPath,
                "fileName" : imageItem.fileName,
                "estimatedSize" : imageItem.estimatedSize,
                "album" : imageItem.album,
                "selected" : false,
                "exifInfo" : imageItem.exifInfo,
                "isSearchResult" : imageItem.isSearchResult,
                "timestampSource" : imageItem.timestampSource,
                "isFavourite" : imageItem.isFavourite
            })
        }
        idListModelImages.clear()
        idListModelImages.append(reversedRowsArray)

        var reversedFavouritesArray = []
        for (i = idListModelFavourites.count -1; i >= 0; --i) {
            var favouriteItem = idListModelFavourites.get(i)
            reversedFavouritesArray.push({
                "creationDateMS" : favouriteItem.creationDateMS,
                "filePath" : favouriteItem.filePath,
                "monthYear" : favouriteItem.monthYear,
                "day" : favouriteItem.day,
                "folderPath" : favouriteItem.folderPath,
                "fileName" : favouriteItem.fileName,
                "estimatedSize" : favouriteItem.estimatedSize,
                "album" : favouriteItem.album,
                "selected" : false,
                "exifInfo" : favouriteItem.exifInfo,
                "isSearchResult" : favouriteItem.isSearchResult,
                "timestampSource" : favouriteItem.timestampSource,
                "isFavourite" : favouriteItem.isFavourite,
                "listModelImages_baseIndex" : favouriteItem.listModelImages_baseIndex
            })
        }
        idListModelFavourites.clear()
        idListModelFavourites.append(reversedFavouritesArray)

        remapBaseIndexes()

        // rebuild an active filter in the new order
        if (timelineAlbumFilter !== "") {
            setTimelineAlbumFilter( timelineAlbumFilter )
        }

        // scroll back so the previously centered image stays centered, its position mirrors in a reversed list
        if (centeredIndex >= 0) {
            idListViewTimeline.positionViewAtIndex( visibleModelCount - 1 - centeredIndex, ListView.Center )
        }
    }

    function addTimelineRowToFavourites( sourceModel, rowIndex, updateType ) {
        // append to the favourites model unless already there, removal happens in updateAllLists_isFavourite
        if (updateType !== "addFavourite") { return }
        for (var k = 0; k < idListModelFavourites.count; k++) {
            if (idListModelFavourites.get(k).filePath === sourceModel.get(rowIndex).filePath) { return }
        }
        idListModelFavourites.append({
                             "creationDateMS" : sourceModel.get(rowIndex).creationDateMS,
                             "filePath" : sourceModel.get(rowIndex).filePath,
                             "monthYear" : sourceModel.get(rowIndex).monthYear,
                             "day" : sourceModel.get(rowIndex).day,
                             "folderPath" : sourceModel.get(rowIndex).folderPath,
                             "fileName" : sourceModel.get(rowIndex).fileName,
                             "estimatedSize" : sourceModel.get(rowIndex).estimatedSize,
                             "album" : sourceModel.get(rowIndex).album,
                             "selected" : false,
                             "exifInfo" :  sourceModel.get(rowIndex).album,
                             "isSearchResult" : false,
                             "timestampSource" : sourceModel.get(rowIndex).timestampSource,
                             "isFavourite" : "true",
                             "listModelImages_baseIndex" : (timelineAlbumFilter !== "") ? sourceModel.get(rowIndex).listModelImages_baseIndex : rowIndex
                         })
    }

    function setTimelineAlbumFilter( albumName ) {
        if (multiSelectActive === true) { unselectAll() } // the selection flags of the rebuilt rows would go stale
        // resolve the centered image to its position in the main list, the filter should land on the closest date instead of the top
        var centeredIndex = centeredTimelineIndex()
        var centeredBaseIndex = -1
        if (centeredIndex >= 0) {
            centeredBaseIndex = (timelineAlbumFilter !== "") ? idListModelTimelineFiltered.get(centeredIndex).listModelImages_baseIndex : centeredIndex
        }
        var centeredDateMS = (centeredBaseIndex >= 0) ? idListModelImages.get(centeredBaseIndex).creationDateMS : 0
        var nearestFilteredIndex = -1
        var passedCenter = false

        timelineAlbumFilter = albumName
        idListModelTimelineFiltered.clear()
        for (var i = 0; i < idListModelImages.count; i++) {
            if (idListModelImages.get(i).album === albumName) {
                // the lists share their chronological order, so the nearest list position is also the nearest date
                if (centeredBaseIndex >= 0 && passedCenter === false) {
                    if (i <= centeredBaseIndex) {
                        nearestFilteredIndex = idListModelTimelineFiltered.count
                    }
                    else {
                        passedCenter = true
                        if (nearestFilteredIndex < 0 || Math.abs(idListModelImages.get(i).creationDateMS - centeredDateMS) < Math.abs(idListModelTimelineFiltered.get(nearestFilteredIndex).creationDateMS - centeredDateMS)) {
                            nearestFilteredIndex = idListModelTimelineFiltered.count
                        }
                    }
                }
                idListModelTimelineFiltered.append({
                    "creationDateMS" : idListModelImages.get(i).creationDateMS,
                    "filePath" : idListModelImages.get(i).filePath,
                    "monthYear" : idListModelImages.get(i).monthYear,
                    "day" : idListModelImages.get(i).day,
                    "folderPath" : idListModelImages.get(i).folderPath,
                    "fileName" : idListModelImages.get(i).fileName,
                    "estimatedSize" : idListModelImages.get(i).estimatedSize,
                    "album" : idListModelImages.get(i).album,
                    "selected" : false,
                    "exifInfo" :  idListModelImages.get(i).album,
                    "isSearchResult" : false,
                    "timestampSource" : idListModelImages.get(i).timestampSource,
                    "isFavourite" : idListModelImages.get(i).isFavourite,
                    "listModelImages_baseIndex" : i
                })
            }
        }

        // scroll to the filtered image closest to the previously centered date, reverseTimelineOrder repositions again afterwards when it is the caller
        if (nearestFilteredIndex >= 0) {
            idListViewTimeline.positionViewAtIndex( nearestFilteredIndex, ListView.Center )
        }
    }

    function applyTimelineAlbumFilter() {
        // drop images whose album no longer matches the active filter, checked against the main list which holds the fresh album values
        if (timelineAlbumFilter === "") { return }
        for (var i = idListModelTimelineFiltered.count -1; i >= 0; --i) {
            if (idListModelImages.get(idListModelTimelineFiltered.get(i).listModelImages_baseIndex).album !== timelineAlbumFilter) {
                idListModelTimelineFiltered.remove(i)
            }
        }
    }

    function setFolderAlbumFilter( albumName ) {
        // re-fill the folder list first, an earlier filter may have hidden images of the newly chosen album
        getImagesInFolder( currentFolder )
        currentFolderAlbumFilter = albumName
        applyFolderAlbumFilter()
    }

    function applyFolderAlbumFilter() {
        if (currentFolderAlbumFilter === "") { return }
        for (var i = idListModelImagesFolder.count -1; i >= 0; --i) {
            if (idListModelImagesFolder.get(i).album !== currentFolderAlbumFilter) {
                idListModelImagesFolder.remove(i)
            }
        }
    }

    function deleteThisImage ( filePathArray, fromPage ) {
        // python deletes the files and reports back what is really gone, all list and DB cleanup happens in removeDeletedFilesFromLists
        deleteRequestSourcePage = fromPage
        py.deleteFilesFunction( filePathArray )
    }

    function removeDeletedFilesFromLists ( deletedPathArray ) {
        var fromPage = deleteRequestSourcePage
        deleteRequestSourcePage = ""

        // remove from DB, checks automatically if available or not, and scrub global image references so nothing keeps loading a dead path
        for (var j = 0; j < deletedPathArray.length; j++) {
            storageItem.removeAlbum(deletedPathArray[j])
            storageItem.removeKeywords(deletedPathArray[j])
            if (coverImagePath === deletedPathArray[j]) { coverImagePath = "" }
            if (lastEditedImagePath === deletedPathArray[j]) { lastEditedImagePath = "" }
            if (currentSlideshowImagePath === deletedPathArray[j] || currentSlideshowImagePath === "file://" + deletedPathArray[j]) { currentSlideshowImagePath = "" }
        }
        lastDeletedPathsArray = deletedPathArray // open pages prune their own image lists through this

        // bugfix: if there are too many images 2 delete, the list counting takes too long and blocks UI, we therefore just call a complete rescan to fill up lists
        if (deletedPathArray.length >= imagesWorkload2Rescan) {
            clearAllLists()
            py.scanForImages()
            return
        }

        var deletedPathsMap = ({})
        for (j = 0; j < deletedPathArray.length; j++) {
            deletedPathsMap[deletedPathArray[j]] = true
        }

        // remove from main image list
        for (var i = idListModelImages.count -1; i >= 0; --i) {
            if (deletedPathsMap[idListModelImages.get(i).filePath] === true) {
                idListModelImages.remove(i)
            }
        }

        // remove from current album list
        for (var k = idListModelImagesAlbum.count -1; k >= 0; --k) {
            if (deletedPathsMap[idListModelImagesAlbum.get(k).filePath] === true) {
                idListModelImagesAlbum.remove(k)
            }
        }

        // remove from current folder list
        for ( var o = idListModelImagesFolder.count -1; o >= 0; --o) {
            if (deletedPathsMap[idListModelImagesFolder.get(o).filePath] === true) {
                idListModelImagesFolder.remove(o)
            }
        }

        // possibly remove from search results list as well
        for ( var l = idListModelSearch.count -1; l >= 0; --l) {
            if (deletedPathsMap[idListModelSearch.get(l).filePath] === true) {
                idListModelSearch.remove(l)
            }
        }

        // possibly remove from favourites list as well
        for ( l = idListModelFavourites.count -1; l >= 0; --l) {
            if (deletedPathsMap[idListModelFavourites.get(l).filePath] === true) {
                idListModelFavourites.remove(l)
            }
        }

        // possibly remove from the filtered timeline as well
        for ( l = idListModelTimelineFiltered.count -1; l >= 0; --l) {
            if (deletedPathsMap[idListModelTimelineFiltered.get(l).filePath] === true) {
                idListModelTimelineFiltered.remove(l)
            }
        }

        // possibly remove from the duplicates results as well
        for ( l = idListModelDuplicates.count -1; l >= 0; --l) {
            if (deletedPathsMap[idListModelDuplicates.get(l).filePath] === true) {
                idListModelDuplicates.remove(l)
            }
        }

        // positions into idListModelImages shifted, re-map the stored indexes so eg. set-album keeps hitting the right image
        remapBaseIndexes()

        // re-count items still left, search results should be kept - empty albums and folders drop out of the rebuilt models automatically
        countDistinctAlbums()
        countDistinctFolders()
        randomizeDistinctFoldersArray()

        // close album- or folder-page, if it was the last image available there
        if ((fromPage === "albumPage") && (idListModelImagesAlbum.count < 1)) { pageStack.pop() }
        if ((fromPage === "folderPage") && (idListModelImagesFolder.count < 1)) { pageStack.pop() }

        // the app cover may have shown one of the deleted images
        randomCoverImage()
    }

    function updateAllLists_isFavourite( fromPage, action, filePathArray ) {
        for (var j = 0; j < filePathArray.length; j++) {
            var filePath = filePathArray[j]

            if (action === "addFavourite") {
                var valueIsFavourite = "true"
                // make new DB entry
                storageItem.addKeywords(filePath, "true")
            }
            else { // action === "removeFavourite from all lists"
                valueIsFavourite = "false"
                // remove from favourites list first and from DB
                for ( var l = idListModelFavourites.count -1; l >= 0; --l) {
                    if (idListModelFavourites.get(l).filePath === filePath) {
                        storageItem.removeKeywords(filePath)
                        idListModelFavourites.remove(l)
                    }
                }
            }

            // update main image list
            for (l = 0; l < idListModelImages.count; l++) {
                if (idListModelImages.get(l).filePath === filePath) {
                    idListModelImages.setProperty(l, "isFavourite", valueIsFavourite)
                }
            }

            // update current album list
            for ( l = idListModelImagesAlbum.count -1; l >= 0; --l) {
                if (idListModelImagesAlbum.get(l).filePath === filePath) {
                    // only when called from inside favourites album, remove from that list, otherwise just mark as non-favourite
                    if (fromPage === "fromFavouritesAlbum") {
                        idListModelImagesAlbum.remove(l)
                        if (idListModelImagesAlbum.count < 1) {
                            pageStack.pop()
                        }
                    }
                    // otherwise just change its property isFavourite
                    else {
                        idListModelImagesAlbum.setProperty(l, "isFavourite", valueIsFavourite)
                    }
                }
            }

            // update current folder list
            for (l = 0; l < idListModelImagesFolder.count; l++) {
                if (idListModelImagesFolder.get(l).filePath === filePath) {
                    idListModelImagesFolder.setProperty(l, "isFavourite", valueIsFavourite)
                }
            }

            // possibly update search results list as well
            for (l = 0; l < idListModelSearch.count; l++) {
                if (idListModelSearch.get(l).filePath === filePath) {
                    idListModelSearch.setProperty(l, "isFavourite", valueIsFavourite)
                }
            }

            // possibly update the filtered timeline as well
            for (l = 0; l < idListModelTimelineFiltered.count; l++) {
                if (idListModelTimelineFiltered.get(l).filePath === filePath) {
                    idListModelTimelineFiltered.setProperty(l, "isFavourite", valueIsFavourite)
                }
            }

            // possibly update the duplicates results as well
            for (l = 0; l < idListModelDuplicates.count; l++) {
                if (idListModelDuplicates.get(l).filePath === filePath) {
                    idListModelDuplicates.setProperty(l, "isFavourite", valueIsFavourite)
                }
            }
        }
        countDistinctAlbums()
    }

    function getAllPathsInAlbumOrFolder(currentView, currentNameOrFolder, intendedAction) {
        // collect all affected file paths
        var imagePathsList = ""
        if (currentView === "albums") {
            // case favourites album
            if (currentNameOrFolder === standardFavouritesAlbum) {
                for (var i = 0; i < idListModelFavourites.count; i++) {
                    imagePathsList = imagePathsList + (idListModelFavourites.get(i).filePath).toString() + "|||"
                }
            }
            // case search album
            else if (currentNameOrFolder === standardSearchAlbum) {
                for (i = 0; i < idListModelSearch.count; i++) {
                    imagePathsList = imagePathsList + (idListModelSearch.get(i).filePath).toString() + "|||"
                }
            }
            // case duplicates album
            else if (currentNameOrFolder === standardDuplicatesAlbum) {
                for (i = 0; i < idListModelDuplicates.count; i++) {
                    imagePathsList = imagePathsList + (idListModelDuplicates.get(i).filePath).toString() + "|||"
                }
            }
            // all other albums
            else {
                for (i = 0; i < idListModelImages.count; i++) {
                    if ( (idListModelImages.get(i).album) === currentNameOrFolder ) {
                        //console.log("pack any other album")
                        imagePathsList = imagePathsList + (idListModelImages.get(i).filePath).toString() + "|||"
                    }
                }
            }
        }
        else { // view: folders
            for (i = 0; i < idListModelImages.count; i++) {
                if ( (idListModelImages.get(i).folderPath) === currentNameOrFolder ) {
                    imagePathsList = imagePathsList + (idListModelImages.get(i).filePath).toString() + "|||"
                }
            }
        }

        // intention...
        if (intendedAction === "createZip") {
            py.packZipImagesTmp( imagePathsList )
        }
        else if (intendedAction === "deleteFiles") {
            var chosenFilesArray = []
            if (imagePathsList.slice(-3) === "|||") {
                imagePathsList = imagePathsList.slice(0, -3)
            }
            chosenFilesArray = imagePathsList.split("|||")
            //console.log(chosenFilesArray)
            deleteThisImage( chosenFilesArray, "firstPage" )
        }
        else if (intendedAction === "bulkResize") {
            var startWidth = 1920
            var startHeight = 1920
            if (imagePathsList.slice(-3) === "|||") {
                imagePathsList = imagePathsList.slice(0, -3)
            }
            bannerResize.notify( startWidth, startHeight, imagePathsList )
        }
    }

    function unselectAll() {
        for (var i = 0; i < idListModelImages.count; i++) {
            if (idListModelImages.get(i).selected === true) {
                idListModelImages.setProperty(i, "selected", false)
            }
        }
        for (i = 0; i < idListModelTimelineFiltered.count; i++) {
            if (idListModelTimelineFiltered.get(i).selected === true) {
                idListModelTimelineFiltered.setProperty(i, "selected", false)
            }
        }
        multiSelectActive = false
        timelineSelectedTotal = 0
    }

    function randomCoverImage() {
        function randomIntFromInterval(min, max) { // min and max included
          return Math.floor(Math.random() * (max - min + 1) + min)
        }
        var randomIndex = randomIntFromInterval(0, idListModelImages.count-1)
        if (idListModelImages.count !== 0) {
            coverImagePath = (idListModelImages.get(randomIndex).filePath).toString()
        } else {
            coverImagePath = ""
        }
    }

    function randomizeCoverAlbumFolderArt() {
        // randomizing app cover image always
        if (!runSlideshowTimer && coverpageActiveFocus) {
            //console.log("cover active, randomizing image")
            randomCoverImage()
        }

        // also assign new random covers for albums while visible
        if (page.activeFocus && currentView === "album") {
            //console.log("randomizing album art")
            countDistinctAlbums()
        }

        // also assign new random covers for folders while visible
        if (page.activeFocus && currentView === "folder") {
            //console.log("randomizing folder art")
            randomizeDistinctFoldersArray()
        }
    }
}

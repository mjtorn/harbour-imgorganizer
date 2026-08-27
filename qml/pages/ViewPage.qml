import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0


Page {
    id: imagePage
    // values from previous page
    property var upperFreeHeight
    property var allCurrentModelImagePathsArray
    property var currentImageIndex

    // own values
    property color buttonBackgroundColor: Theme.rgba(Theme.highlightDimmerColor, 1)
    property var currentImagePath : allCurrentModelImagePathsArray[currentImageIndex]
    property var trackedDeletedPaths : lastDeletedPathsArray // watchdog pattern: prune deleted files so swiping and the slideshow never hit them
    onTrackedDeletedPathsChanged: {
        if (trackedDeletedPaths.length === 0 || status !== PageStatus.Active) { return }
        var shownPath = currentImagePath
        var cleanedPathsArray = []
        for (var i = 0; i < allCurrentModelImagePathsArray.length; i++) {
            if (trackedDeletedPaths.indexOf(allCurrentModelImagePathsArray[i]) === -1) {
                cleanedPathsArray.push(allCurrentModelImagePathsArray[i])
            }
        }
        if (cleanedPathsArray.length === allCurrentModelImagePathsArray.length) { return } // nothing shown here was deleted
        if (cleanedPathsArray.length === 0) {
            pageStack.pop()
            return
        }
        allCurrentModelImagePathsArray = cleanedPathsArray
        var newIndex = cleanedPathsArray.indexOf(shownPath)
        currentImageIndex = (newIndex !== -1) ? newIndex : Math.min(currentImageIndex, cleanedPathsArray.length - 1)
    }
    // tap-to-toggle info overlay, stays visible across image switches, hidden by default
    property bool showImageInfo : false
    property var currentImageInfo : ({ "fileName" : "", "folderPath" : "", "dateText" : "", "album" : "", "isFavourite" : "false" })
    onShowImageInfoChanged: refreshImageInfo()
    onCurrentImagePathChanged: refreshImageInfo()

    function refreshImageInfo() {
        if (showImageInfo === false) { return } // costs nothing while the overlay is hidden
        var infoObject = ({ "fileName" : "", "folderPath" : "", "dateText" : "", "album" : "", "isFavourite" : "false" })
        for (var i = 0; i < idListModelImages.count; i++) {
            if (idListModelImages.get(i).filePath === currentImagePath) {
                var imageItem = idListModelImages.get(i)
                infoObject.fileName = imageItem.fileName
                infoObject.folderPath = imageItem.folderPath
                infoObject.dateText = imageItem.day + ". " + imageItem.monthYear + "   " + (new Date(imageItem.creationDateMS * 1000)).toLocaleTimeString(Qt.locale(), "hh:mm")
                infoObject.album = (imageItem.album[0] === ".") ? imageItem.album.substring(1) : imageItem.album
                infoObject.isFavourite = imageItem.isFavourite
            }
        }
        currentImageInfo = infoObject
    }

    Connections {
        // the album was just set from this viewer, a counter avoids resetting a watched value in its own handler
        target: page
        onAlbumAssignmentCounterChanged: {
            refreshImageInfo() // the info overlay would otherwise keep showing the old album
            if (albumAssignmentLeftTheView === true) {
                idCloseAfterAlbumTimer.start() // deferred, the album banner is still finishing its click handler
            }
        }
    }
    Connections {
        // the shown file may have just been renamed, follow it under the new name
        target: page
        onFileRenameCounterChanged: {
            var updatedPathsArray = allCurrentModelImagePathsArray.slice(0) // a new array, the path binding reacts to the reference
            var changedAny = false
            for (var i = 0; i < updatedPathsArray.length; i++) {
                if (updatedPathsArray[i] === lastRenamedOldPath) {
                    updatedPathsArray[i] = lastRenamedNewPath
                    changedAny = true
                }
            }
            if (changedAny === true) {
                allCurrentModelImagePathsArray = updatedPathsArray
                refreshImageInfo()
            }
        }
    }
    Timer {
        id: idCloseAfterAlbumTimer
        interval: 1
        onTriggered: {
            pageStack.pop()
        }
    }

    property string trackedEditedImagePath : lastEditedImagePath // watchdog pattern: an edit saved a new copy, show it right away
    onTrackedEditedImagePathChanged: {
        if (trackedEditedImagePath !== "") {
            // swap the copy into the path array instead of assigning currentImagePath, that would break its binding and kill swiping
            var updatedPathsArray = allCurrentModelImagePathsArray
            updatedPathsArray[currentImageIndex] = trackedEditedImagePath
            allCurrentModelImagePathsArray = updatedPathsArray
        }
    }
    property bool finishedLoadingView : false
    property real minMouseMoveXSwipeImage : Theme.itemSizeMedium
    property real flickScale : flick.contentWidth / flick.width
    property bool firstTimeLoading : true
    property bool pinchEnabled : true

    property real imageSourceWidth : idImageView.sourceSize.width
    property real imageSourceHeight : idImageView.sourceSize.height
    property real imagePaintedWidth : idImageView.paintedWidth
    property real imagePaintedHeight : idImageView.paintedHeight

    property real imageRatioSourceScreen : imageSourceWidth / imagePaintedWidth


    // slideshow
    property real slideshowTimerProgress : 0
    property real targetDateMS

    allowedOrientations: Orientation.All
    backNavigation: false
    onOrientationChanged: {
        if (firstTimeLoading === false) {
            // had to exchange flick.width with flick.height at every occurance in this line ... why?
            flick.resizeContent(flick.height, flick.width, Qt.point(flick.height/2, flick.width/2))
            flick.returnToBounds()
        }
    }
    backgroundColor: "black"
    Component.onCompleted: {
        viewpageActiveFocus = true
    }
    Component.onDestruction: {
        viewpageActiveFocus = false
    }

    Timer {
        id: idSlideshowChangeTimer
        interval: coverImageChangeInterval // [ms}
        running: runSlideshowTimer && finishedLoading
        repeat: true
        onRunningChanged: {
            // first start also triggers a reset of the progress bar
            if (running === true) {
                resetCountdownTimer()
            }
        }
        onTriggered: {
            if (currentImageIndex < allCurrentModelImagePathsArray.length-1) {
                currentImageIndex = currentImageIndex + 1
                resetCountdownTimer()
            }
            else {
                animateRightListEnd.start()
                stopSlideshow()
            }
        }
    }
    Timer {
        id: idTimerClock
        interval: 10
        running: idSlideshowChangeTimer.running
        repeat: true
        onRunningChanged: {
            // first start also triggers a reset of the progress bar
            if (running === true) {
                var nowDateMS = new Date().getTime()
                slideshowTimerProgress = (targetDateMS - nowDateMS) / coverImageChangeInterval
            }
        }
        onTriggered: {
            var nowDateMS = new Date().getTime()
            slideshowTimerProgress = (targetDateMS - nowDateMS) / coverImageChangeInterval
        }
    }
    BannerTools {
        id: bannerTools
    }
    BannerCrop {
        id: bannerCrop
    }
    BannerColorize {
        id: bannerColorize
    }
    BannerResize {
        id: bannerResize
    }
    BannerPaint {
        id: bannerPaint
    }
    BannerToAlbum {
        id: bannerToAlbumFromView
    }
    BannerRenameFile {
        id: bannerRenameFileFromView
    }
    NumberAnimation {
        id: animateLeftListEnd
        target: idLeftListEnd
        properties: "opacity"
        from: 1
        to: 0
        loops: 1 //Animation.Infinite
        duration: 750
    }
    NumberAnimation {
        id: animateRightListEnd
        target: idRightListEnd
        properties: "opacity"
        from: 1
        to: 0
        loops: 1 //Animation.Infinite
        duration: 750
    }

    Rectangle {
        id: root
        //anchors.fill: parent
        width: isPortrait ? appWidth : appHeight // needed to not resize image when keyboard shows up
        height: isPortrait ? appHeight : appWidth // needed to not resize image when keyboard shows up
        color: "black" // background color prevents theme shining through for some milliseconds during rotation

        SilicaFlickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            PinchArea {
                id: pinchArea
                width: Math.max(flick.contentWidth, flick.width)
                height: Math.max(flick.contentHeight, flick.height)
                enabled: pinchEnabled

                property real initialWidth_Pinch
                property real initialHeigth_Pinch

                onPinchStarted: {
                    stopSlideshow()
                    initialWidth_Pinch = flick.contentWidth
                    initialHeigth_Pinch = flick.contentHeight
                }
                onPinchUpdated: {
                    var newWidth = initialWidth_Pinch * pinch.scale
                    var newHeight = initialHeigth_Pinch * pinch.scale
                    if (newWidth < flick.width || newHeight < flick.height ) {
                        flick.resizeContent(flick.width, flick.height, Qt.point(flick.width/2, flick.height/2))
                    }
                    else {
                        flick.contentX += pinch.previousCenter.x - pinch.center.x
                        flick.contentY += pinch.previousCenter.y - pinch.center.y
                        flick.resizeContent(initialWidth_Pinch * pinch.scale, initialHeigth_Pinch * pinch.scale, pinch.center)
                    }
                }
                onPinchFinished: {
                    flick.returnToBounds()
                }

                Image {
                    id: idImageView
                    anchors.centerIn: parent
                    width: flick.contentWidth
                    height: flick.contentHeight
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true
                    source: (reloadImage === false && currentImagePath !== undefined) ? currentImagePath : ""
                    cache: false
                    onStatusChanged: {
                        if (status === Image.Loading) {
                            finishedLoadingView = false
                        }
                        else if (status === Image.Ready) {
                            finishedLoadingView = true
                            firstTimeLoading = false
                            currentSlideshowImagePath = source
                        }
                    }

                    AnimatedImage {
                        // Image only ever shows the first frame of a gif, this overlay plays the animation on top of it
                        anchors.fill: parent
                        visible: (currentImagePath !== undefined) && (currentImagePath.toString().toLowerCase().slice(-4) === ".gif") && (idImageView.status === Image.Ready)
                        playing: visible
                        fillMode: Image.PreserveAspectFit
                        source: visible ? idImageView.source : ""
                        cache: false
                    }
                    MouseArea {
                        id: idMouseAreaFlick
                        enabled: flickScale !== 1 && idImageView.status !== Image.Loading
                        hoverEnabled: true
                        anchors.fill: parent
                        onDoubleClicked: {
                            flick.contentWidth = flick.width
                            flick.contentHeight = flick.height
                            flick.contentX = 0
                            flick.contentY = 0
                            flick.returnToBounds()
                            // faster but gives strange animation
                            //flick.resizeContent(flick.contentWidth*1.5, flick.contentHeight*1.5, Qt.point(mouseX, mouseY))
                            //flick.resizeContent(flick.width, flick.height, Qt.point(flick.width/2, flick.height/2))
                        }
                    }
                    MouseArea {
                        id: idMouseAreaSwipe
                        enabled: flickScale === 1 && idImageView.status !== Image.Loading
                        anchors.fill: parent
                        anchors.topMargin: upperFreeHeight

                        property var position : {"x":0, "y":x}
                        property var limitMouseDistanceSwipe
                        /*
                        onPressAndHold: {
                            if (pillowAvailable) {
                                bannerTools.notify()
                            }
                        }
                        */
                        onEntered: {
                            stopSlideshow()
                            limitMouseDistanceSwipe = false
                            position.x = mouseX
                            position.y = mouseY
                        }
                        onMouseXChanged: {
                            if (limitMouseDistanceSwipe === false) {
                                if (mouseX - position.x > minMouseMoveXSwipeImage && Math.abs(mouseY - position.y) < minMouseMoveXSwipeImage) {
                                    //console.log(swipe right = go backwards")
                                    limitMouseDistanceSwipe = true
                                    if (currentImageIndex > 0) {
                                        currentImageIndex = currentImageIndex - 1
                                    }
                                    else {
                                        animateLeftListEnd.start()
                                    }
                                }
                                else if (position.x - mouseX > minMouseMoveXSwipeImage && Math.abs(mouseY - position.y) < minMouseMoveXSwipeImage) {
                                    //console.log(swipe left = go foreward")
                                    limitMouseDistanceSwipe = true
                                    if (currentImageIndex < allCurrentModelImagePathsArray.length-1) {
                                        currentImageIndex = currentImageIndex + 1
                                    }
                                    else {
                                        animateRightListEnd.start()
                                    }
                                }
                            }
                        }
                        onReleased: {
                            limitMouseDistanceSwipe = false
                        }
                        onClicked: {
                            // only a real tap toggles the info overlay, not the tail end of a swipe
                            if (Math.abs(mouseX - position.x) < Theme.paddingLarge && Math.abs(mouseY - position.y) < Theme.paddingLarge) {
                                showImageInfo = !showImageInfo
                            }
                        }
                    }


                }
                BrightnessContrast {
                    id: idImagePreviewColors
                    enabled: pillowAvailable && bannerColorize.opacity === 1
                    visible: enabled
                    anchors.fill: idImageView
                    source: idImageView
                    brightness: 0
                    contrast: 0
                }
            }
        }
        Rectangle {
            id: idImageInfoOverlay
            visible: showImageInfo && (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            anchors.top: parent.top
            anchors.topMargin: upperFreeHeight
            width: parent.width
            height: idColumnImageInfo.height + Theme.paddingLarge
            color: Theme.rgba(Theme.overlayBackgroundColor, 0.7)

            Column {
                id: idColumnImageInfo
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2*Theme.paddingLarge

                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                    text: currentImageInfo.fileName
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                    text: currentImageInfo.folderPath
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.primaryColor
                    text: currentImageInfo.dateText
                }
                Label {
                    visible: imageSourceWidth > 0
                    width: parent.width
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.primaryColor
                    text: imageSourceWidth + " × " + imageSourceHeight
                }
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium

                    Label {
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.primaryColor
                        font.bold: true
                        text: currentImageInfo.album
                    }
                    Icon {
                        visible: currentImageInfo.isFavourite === "true"
                        width: Theme.iconSizeExtraSmall
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-favorite-selected?"
                    }
                }
            }
        }
        IconButton {
            id: idButtonClose
            anchors.left: parent.left
            visible: (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            height: upperFreeHeight
            width: height
            icon.scale: 1
            icon.source: "image://theme/icon-m-cancel?"
            onClicked: {
                stopSlideshow()
                //viewpageActiveFocus = false
                pageStack.pop()
            }

            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width / 3*2
                height: width
                radius: width/2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
            }
        }
        IconButton {
            id: idButtonRenameFile
            anchors {
                horizontalCenter: isPortrait ? parent.horizontalCenter : parent.left
                horizontalCenterOffset: isPortrait ? -parent.width/4 : width/2
                verticalCenter: isPortrait ? parent.top : parent.verticalCenter
                verticalCenterOffset: isPortrait ? height/2 : -parent.height/4
            }
            visible: (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            height: upperFreeHeight
            width: height
            icon.scale: 1
            icon.source: "image://theme/icon-m-note?"
            onClicked: {
                stopSlideshow()
                var shownFileName = (currentImagePath.toString()).substring((currentImagePath.toString()).lastIndexOf("/") + 1)
                bannerRenameFileFromView.notify( currentImagePath.toString(), shownFileName )
            }

            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width / 3*2
                height: width
                radius: width/2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
            }
        }
        IconButton {
            id: idButtonSlideshow
            anchors {
                horizontalCenter: isPortrait ? parent.horizontalCenter : parent.left
                horizontalCenterOffset: isPortrait ? 0 : width/2
                verticalCenter: isPortrait ? parent.top : parent.verticalCenter
                verticalCenterOffset: isPortrait ? height/2 : 0
            }
            visible: (pillowAvailable) && (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            height: upperFreeHeight
            width: height
            //icon.scale: 1.9
            icon.source: runSlideshowTimer ? ("image://theme/icon-cover-pause?") : ("image://theme/icon-cover-play?")
            onClicked: {
                if (currentImageIndex < allCurrentModelImagePathsArray.length-1) {
                    runSlideshowTimer ? runSlideshowTimer = false : runSlideshowTimer = true
                }
                else {
                    animateRightListEnd.start()
                }
            }

            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width / 3*2
                height: width
                radius: width/2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
            }
            ProgressCircle {
                id: idProgressCircle
                scale: 0.85
                visible: runSlideshowTimer
                anchors.fill: parent
                backgroundColor: "transparent" //Theme.darkPrimaryColor
                progressColor: Theme.secondaryHighlightColor
                inAlternateCycle: false
                value: 1-slideshowTimerProgress
            }
        }
        IconButton {
            id: idButtonSetAlbum
            anchors {
                horizontalCenter: isPortrait ? parent.horizontalCenter : parent.left
                horizontalCenterOffset: isPortrait ? parent.width/4 : width/2
                verticalCenter: isPortrait ? parent.top : parent.verticalCenter
                verticalCenterOffset: isPortrait ? height/2 : parent.height/4
            }
            visible: (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            height: upperFreeHeight
            width: height
            icon.scale: 1
            icon.source: "image://theme/icon-m-folder?"
            onClicked: {
                stopSlideshow()
                // the album assignment works on the position in the main list, whichever list opened the viewer
                var baseIndex = -1
                for (var i = 0; i < idListModelImages.count; i++) {
                    if (idListModelImages.get(i).filePath === currentImagePath) {
                        baseIndex = i
                    }
                }
                if (baseIndex >= 0) {
                    bannerToAlbumFromView.notify( Theme.highlightDimmerColor, Theme.itemSizeHuge, [ [0, currentImagePath, baseIndex] ], "fromViewPage", "triggeredOnViewPage" )
                }
            }

            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width / 3*2
                height: width
                radius: width/2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
            }
        }
        IconButton {
            id: idButtonEdit
            anchors.right: isPortrait ? parent.right : parent.left
            anchors.rightMargin: isPortrait ? 0 : -width
            anchors.top: isPortrait ? parent.top : parent.bottom
            anchors.topMargin: isPortrait ? 0 : -height
            visible: (pillowAvailable) && (flickScale === 1) && (bannerCrop.opacity === 0) && (bannerColorize.opacity === 0) && (bannerResize.opacity === 0) && (bannerTools.opacity === 0) && (bannerPaint.opacity === 0) && (bannerToAlbumFromView.opacity === 0) && (bannerRenameFileFromView.opacity === 0)
            height: upperFreeHeight
            width: height
            icon.scale: 1
            icon.source: "image://theme/icon-m-edit?"
            onClicked: {
                stopSlideshow()
                if (pillowAvailable) {
                    bannerTools.notify()
                }
            }

            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width / 3*2
                height: width
                radius: width/2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
            }
        }

        Rectangle {
            id: idLeftListEnd
            opacity: 0
            y: Theme.itemSizeLarge
            width: Theme.paddingSmall
            height: parent.height - 2*y
            color: Theme.errorColor
        }
        Rectangle {
            id: idRightListEnd
            opacity: 0
            y: Theme.itemSizeLarge
            width: Theme.paddingSmall
            height: parent.height - 2*y
            color: Theme.errorColor
            anchors.right: parent.right
        }
        BusyIndicator {
            anchors.centerIn: parent
            running: finishedLoadingView === false
            size: BusyIndicatorSize.Large
        }
    }


    function freezeOrientation() {
        if (isPortrait === true) {
            allowedOrientations = Orientation.PortraitMask
        }
        else {
            allowedOrientations = Orientation.LandscapeMask
        }
    }

    function stopSlideshow() {
        slideshowTimerProgress = 100
        runSlideshowTimer = false
    }

    function resetCountdownTimer(){
        slideshowTimerProgress = 0
        var startDateMS = (new Date()).getTime()
        targetDateMS = startDateMS + coverImageChangeInterval
    }
}

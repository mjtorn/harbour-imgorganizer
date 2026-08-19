import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupAlbums
    z: 10
    width: parent.width
    height: parent.height
    visible: opacity > 0
    opacity: 0.0
    onClicked: {
        hide()
    }

    // UI variables
    property var targetAlbumPathList : []
    property string triggeredFrom : ""
    property string triggeredOn: ""
    property bool filterMode : false // pick an album as folder filter instead of assigning it, no album creation
    property var pickerExpandedPrefixes : ({}) // which album name prefixes are expanded, kept across opens so repeated assignments need no re-expanding

    ListModel {
        id: idListModelAlbumPicker
    }

    function buildAlbumPickerTree() {
        // same "Foo / Bar / Baz" coalescing as the album view, structure only - groups expand on tap, only leaves are pickable
        var nodeByPrefix = ({})
        var prefixList = []
        for (var i = 0; i < idListModelAlbums.count; i++) {
            var fullName = idListModelAlbums.get(i).album_name
            if (fullName !== standardSearchAlbum && fullName !== standardFavouritesAlbum && fullName !== standardDuplicatesAlbum) {
                var isSpecialAlbum = (fullName === standardAlbum)
                var nameParts = isSpecialAlbum ? [fullName] : fullName.split(" / ")
                var prefix = ""
                for (var p = 0; p < nameParts.length; p++) {
                    var parentPrefix = prefix
                    prefix = (p === 0) ? nameParts[p] : prefix + " / " + nameParts[p]
                    if (nodeByPrefix[prefix] === undefined) {
                        nodeByPrefix[prefix] = { "displayName" : (isSpecialAlbum ? nameParts[p].substring(1) : nameParts[p]), "parentPrefix" : parentPrefix, "depth" : p, "isAlbum" : false, "hasChildren" : false }
                        prefixList.push(prefix)
                    }
                    if (p === nameParts.length - 1) {
                        nodeByPrefix[prefix].isAlbum = true
                    }
                    else {
                        nodeByPrefix[prefix].hasChildren = true
                    }
                }
            }
        }

        prefixList.sort()
        idListModelAlbumPicker.clear()
        for (i = 0; i < prefixList.length; i++) {
            var node = nodeByPrefix[prefixList[i]]
            var visibleRow = true
            var ancestorPrefix = node.parentPrefix
            while (ancestorPrefix !== "") {
                if (pickerExpandedPrefixes[ancestorPrefix] !== true) { visibleRow = false }
                ancestorPrefix = nodeByPrefix[ancestorPrefix].parentPrefix
            }
            if (visibleRow === true) {
                var expandMarker = (node.hasChildren === true) ? ((pickerExpandedPrefixes[prefixList[i]] === true) ? "▼ " : "▶ ") : ""
                idListModelAlbumPicker.append({ "album_name" : prefixList[i],
                                                "display_name" : expandMarker + ((node.depth === 0) ? node.displayName : prefixList[i]),
                                                "is_group" : node.hasChildren
                                              })
                // every expanded group gets an own selectable leaf row - this is also how an image
                // is assigned to a parent album that so far only exists as a prefix of its sub-albums
                if (node.hasChildren === true && pickerExpandedPrefixes[prefixList[i]] === true) {
                    idListModelAlbumPicker.append({ "album_name" : prefixList[i],
                                                    "display_name" : prefixList[i],
                                                    "is_group" : false
                                                  })
                }
            }
        }
    }

    function togglePickerGroup( groupPrefix ) {
        if (pickerExpandedPrefixes[groupPrefix] === true) {
            delete pickerExpandedPrefixes[groupPrefix]
        }
        else {
            pickerExpandedPrefixes[groupPrefix] = true
        }
        buildAlbumPickerTree()
    }

    Behavior on opacity {
        FadeAnimator {}
    }
    Rectangle {
        id: mainBackgroundRect
        anchors.fill: parent
        color: hideBackColor

        Rectangle {
            id: idBackgroundRect
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: parent.width - 2*Theme.paddingMedium
            height: parent.height - anchors.topMargin - Theme.paddingLarge - Theme.paddingSmall
            radius: Theme.paddingLarge
            border.width: 2
            border.color: Theme.highlightColor

            SilicaFlickable {
                anchors.fill: parent
                contentHeight: idColumnAlbumBanner.height
                clip: true

                Column {
                    id: idColumnAlbumBanner
                    width: parent.width

                    Item {
                        width: parent.width
                        height: Theme.paddingLarge
                    }
                    IconButton {
                        visible: (filterMode === false)
                        enabled: visible
                        width: parent.width
                        //height: Theme.iconSizeSmall
                        icon.source: (idTextFieldNewAlbum.visible === false) ? ("image://theme/icon-m-add?") : ("image://theme/icon-m-remove?")
                        onClicked: {
                            (idTextFieldNewAlbum.visible === false) ? (idTextFieldNewAlbum.visible = true) : (idTextFieldNewAlbum.visible = false)
                            if (idTextFieldNewAlbum.visible === true) {
                                idTextFieldNewAlbum.text = ""
                                idTextFieldNewAlbum.focus = true
                                idTextFieldNewAlbum.forceActiveFocus()
                            }
                            else {
                                idTextFieldNewAlbum.focus = false
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: Theme.paddingLarge
                    }

                    // create a new album
                    TextField {
                        id: idTextFieldNewAlbum
                        visible: false
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.highlightColor
                        inputMethodHints: Qt.ImhNoPredictiveText
                        //validator: RegExpValidator { regExp: /[a-zA-Z0-9äöüÄÖÜ_=()\/.!?#+-]*$/ }
                        placeholderText: qsTr("new album")
                        EnterKey.onClicked: {
                            if (text.length > 0) {
                                idListModelAlbums.append({"album_name" : text })
                                for (var j = 0; j < targetAlbumPathList.length; j++) {
                                    setModelImagesAndDB( j, targetAlbumPathList[j], text )
                                }
                                if (triggeredFrom === "fromFolder") {
                                    applyFolderAlbumFilter()
                                }
                                else if (triggeredFrom === "fromTimeline") {
                                    applyTimelineAlbumFilter()
                                }
                                text = ""
                                hide()
                            }
                        }
                        onTextChanged: {
                            if (acceptableInput) {
                                if (text === standardAlbum || text === standardSearchAlbum) {
                                    text = qsTr("new") + text
                                }
                            }
                        }
                    }

                    // existing albums
                    ListView {
                        id: idListViewBooksLongname
                        width: parent.width
                        height: contentHeight

                        model: idListModelAlbumPicker
                        delegate: ListItem {
                            contentX: idBackgroundRect.radius
                            contentWidth: parent.width - 2* contentX
                            contentHeight: Theme.itemSizeExtraSmall
                            onClicked: {
                                // a group row only expands or collapses its sub-albums, the picker stays open
                                if (is_group === true) {
                                    togglePickerGroup( album_name )
                                    return
                                }
                                if (filterMode === true) {
                                    if (triggeredFrom === "fromTimeline") {
                                        setTimelineAlbumFilter( album_name )
                                    }
                                    else {
                                        setFolderAlbumFilter( album_name )
                                    }
                                }
                                else {
                                    for (var j = 0; j < targetAlbumPathList.length; j++) {
                                        setModelImagesAndDB( j, targetAlbumPathList[j], album_name )
                                    }
                                    // images set to another album must leave the currently filtered view
                                    if (triggeredFrom === "fromFolder") {
                                        applyFolderAlbumFilter()
                                    }
                                    else if (triggeredFrom === "fromTimeline") {
                                        applyTimelineAlbumFilter()
                                    }
                                }
                                hide()
                            }
                            Label {
                                text: display_name
                                color: Theme.primaryColor
                                font.bold: (is_group === true || album_name[0] === ".")
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }

        }
    }


    function notify( color, upperMargin, chosenFilesArray, detailTrigger, triggerPage, filterOnly ) {
        triggeredFrom = detailTrigger
        triggeredOn = triggerPage
        filterMode = (filterOnly === true)
        if (color && (typeof(color) != "undefined")) { idBackgroundRect.color = color }
        else { idBackgroundRect.color = Theme.rgba(Theme.highlightDimmerColor, 1) }
        if (upperMargin && (typeof(upperMargin) != "undefined")) { idBackgroundRect.anchors.topMargin = upperMargin }
        else { idBackgroundRect.height = page.height / 2 }
        targetAlbumPathList = chosenFilesArray
        buildAlbumPickerTree() // rebuilt on every open, the album list may have changed - expansion state is kept
        idFooterRow.visible = false
        popupAlbums.opacity = 1.0
    }

    function hide() {
        idTextFieldNewAlbum.focus = false
        idTextFieldNewAlbum.visible = false
        idFooterRow.visible = true
        countDistinctAlbums( "standard" )
        popupAlbums.opacity = 0.0
        if (triggeredOn !== "triggeredOnFirstPage") {
            unselectAll()
        }
    }

    function setModelImagesAndDB( targetIndex, targetImagePathListArray, targetAlbumName ) { // ToDo: this takes way too long for larger amount of images
        var targetIndex_FolderOrAlbum = targetImagePathListArray[0]
        var targetImagePath = targetImagePathListArray[1]
        var targetImage_listModelImages_baseIndex = targetImagePathListArray[2]

        // save info to IPTC tag if available and wanted
        if (settingUseExif !== 0) {
            if ( targetAlbumName !== standardAlbum) {
                py.insertMetadataKeywords ( targetAlbumName, targetImagePath )
            }
            else {
                py.removeMetadataKeywords ( targetImagePath )
            }
        }

        // update DB info
        if (targetAlbumName !== standardAlbum) {
            storageItem.addAlbum(targetImagePath, targetAlbumName)
        }
        else {
            storageItem.removeAlbum(targetImagePath)
        }

        // update lists
        if (triggeredFrom === "fromTimeline" || triggeredFrom === "fromFolder") { // uses index of main list only

            // update album in main list
            idListModelImages.setProperty(targetImage_listModelImages_baseIndex, "album", targetAlbumName)

            // update album when called from inside a folder list (multi-selected images only)
            if (triggeredFrom === "fromFolder") {
                idListModelImagesFolder.setProperty(targetIndex_FolderOrAlbum, "album", targetAlbumName)
            }
        }

        else if (triggeredFrom === "fromAlbum") { // treats index as the index from albumList
            for (var j = 0; j < idListModelImages.count; j++) {
                if (idListModelImages.get(j).filePath === targetImagePath) {
                    idListModelImages.setProperty(j, "album", targetAlbumName)
                }
            }
            for (var l=idListModelImagesAlbum.count -1 ; l >= 0; --l) {
                if ( (idListModelImagesAlbum.get(l).filePath).toString() === (targetImagePath).toString() ) {
                    if ( (idListModelImagesAlbum.get(l).album).toString() !== (targetAlbumName).toString() ) {
                        // DUPLICATES is not a filter but a finding: filing an image does not stop it being a duplicate
                        if ( currentAlbum !== standardFavouritesAlbum && currentAlbum !== standardSearchAlbum && currentAlbum !== standardDuplicatesAlbum ) {
                            idListModelImagesAlbum.remove(l)
                        }
                    }
                }
            }

            if (idListModelImagesAlbum.count < 1) {
                for (var k = idListModelAlbums.count -1; k >= 0; --k) {
                    if ((idListModelAlbums.get(k).album_name === currentAlbum)) {
                        idListModelAlbums.remove(k)
                    }
                }
                pageStack.pop()
            }
        }
    }

}

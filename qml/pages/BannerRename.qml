import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupRename
    z: 10
    width: parent.width
    height: parent.height
    visible: opacity > 0
    opacity: 0.0
    onClicked: {
        hide()
    }

    // UI variables
    property string oldAlbumName : ""
    property bool renameGroupMode : false // renaming a tree node re-prefixes every album underneath it

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
            anchors.bottom: parent.bottom
            anchors.bottomMargin: upperFreeHeight
            width: parent.width - 2*Theme.paddingMedium
            height: Theme.itemSizeHuge
            radius: Theme.paddingLarge
            border.width: 2
            border.color: Theme.highlightColor

            TextField {
                id: idTextFieldRename
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: Theme.highlightColor
                text: oldAlbumName
                inputMethodHints: Qt.ImhNoPredictiveText
                //validator: RegExpValidator { regExp: /[a-zA-Z0-9äöüÄÖÜ_=()\/.!?#+-]*$/ }
                EnterKey.onClicked: {
                    if (text.length > 0) {
                        if (renameGroupMode === true) {
                            renameAlbumTree_DB( text )
                        }
                        else {
                            renameAlbum_DB( text )
                        }
                        focus = false
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
        }

    }


    function notify( color, albumName, groupRename ) {
        if (color && (typeof(color) != "undefined")) { idBackgroundRect.color = color }
        else { idBackgroundRect.color = Theme.rgba(Theme.highlightDimmerColor, 1) }
        oldAlbumName = albumName
        renameGroupMode = (groupRename === true)

        idTextFieldRename.focus = true
        idFooterRow.visible = false
        popupRename.opacity = 1.0
    }

    function hide() {
        idTextFieldRename.focus = false
        idFooterRow.visible = true
        popupRename.opacity = 0.0
    }

    function albumMatchesPrefix( albumValue, prefixValue ) {
        // strict boundary match: the exact name or a real path child - "Foo" must never touch "Foobar / x"
        return (albumValue === prefixValue) || (albumValue.slice(0, prefixValue.length + 3) === prefixValue + " / ")
    }

    function renameAlbumTree_DB( text ) {
        // every album at or below the old prefix gets the typed text as its new prefix:
        // renaming "Foo" to "Kala" turns "Foo / Bar / Baz" into "Kala / Bar / Baz", and
        // renaming the node "Foo / Bar" to "Kala" re-roots its subtree as "Kala / Baz"
        if (oldAlbumName === text) { return }

        var metadataActive = parseInt(storageItem.getSetting("infoTimeUseExifAlbum", 0))

        // main list and DB rows, metadata keywords when enabled
        for (var j = 0; j < idListModelImages.count; j++) {
            if (albumMatchesPrefix(idListModelImages.get(j).album, oldAlbumName)) {
                var newAlbumName = text + (idListModelImages.get(j).album).substring(oldAlbumName.length)
                idListModelImages.setProperty(j, "album", newAlbumName)
                storageItem.addAlbum(idListModelImages.get(j).filePath, newAlbumName)
                if (metadataActive !== 0) {
                    py.insertMetadataKeywords ( newAlbumName, idListModelImages.get(j).filePath )
                }
            }
        }

        // every other list that carries the album role
        for (var i = 0; i < idListModelImagesAlbum.count; i++) {
            if (albumMatchesPrefix(idListModelImagesAlbum.get(i).album, oldAlbumName)) {
                idListModelImagesAlbum.setProperty(i, "album", text + (idListModelImagesAlbum.get(i).album).substring(oldAlbumName.length))
            }
        }
        for (var k = 0; k < idListModelFavourites.count; k++) {
            if (albumMatchesPrefix(idListModelFavourites.get(k).album, oldAlbumName)) {
                idListModelFavourites.setProperty(k, "album", text + (idListModelFavourites.get(k).album).substring(oldAlbumName.length))
            }
        }
        for (k = 0; k < idListModelSearch.count; k++) {
            if (albumMatchesPrefix(idListModelSearch.get(k).album, oldAlbumName)) {
                idListModelSearch.setProperty(k, "album", text + (idListModelSearch.get(k).album).substring(oldAlbumName.length))
            }
        }
        for (k = 0; k < idListModelImagesFolder.count; k++) {
            if (albumMatchesPrefix(idListModelImagesFolder.get(k).album, oldAlbumName)) {
                idListModelImagesFolder.setProperty(k, "album", text + (idListModelImagesFolder.get(k).album).substring(oldAlbumName.length))
            }
        }
        for (k = 0; k < idListModelDuplicates.count; k++) {
            if (albumMatchesPrefix(idListModelDuplicates.get(k).album, oldAlbumName)) {
                idListModelDuplicates.setProperty(k, "album", text + (idListModelDuplicates.get(k).album).substring(oldAlbumName.length))
            }
        }
        for (k = 0; k < idListModelTimelineFiltered.count; k++) {
            if (albumMatchesPrefix(idListModelTimelineFiltered.get(k).album, oldAlbumName)) {
                idListModelTimelineFiltered.setProperty(k, "album", text + (idListModelTimelineFiltered.get(k).album).substring(oldAlbumName.length))
            }
        }

        // carry the expansion states of the moved subtree over to the new prefix
        var newExpandedPrefixes = ({})
        for (var expandedPrefix in expandedAlbumPrefixes) {
            if (albumMatchesPrefix(expandedPrefix, oldAlbumName)) {
                newExpandedPrefixes[text + expandedPrefix.substring(oldAlbumName.length)] = true
            }
            else {
                newExpandedPrefixes[expandedPrefix] = true
            }
        }
        expandedAlbumPrefixes = newExpandedPrefixes

        if (idListModelSearch.count < 1) {
            countDistinctAlbums( "standard" )
        }
        else {
            countDistinctAlbums( "fromSearch" )
        }
    }

    function renameAlbum_DB( text ) {
        if (oldAlbumName !== text) {

            var metadataActive = parseInt(storageItem.getSetting("infoTimeUseExifAlbum", 0))

            // rename album in distinct album list
            for (var h = 0; h < idListModelAlbums.count; h++) {
                if (idListModelAlbums.get(h).album_name === oldAlbumName) {
                    idListModelAlbums.setProperty(h, "album_name", text)
                }
            }
            // rename album-info in current image list
            for (var i = 0; i < idListModelImagesAlbum.count; i++) {
                if (idListModelImagesAlbum.get(i).album === oldAlbumName) {
                    idListModelImagesAlbum.setProperty(i, "album", text)
                }
            }

            // rename all images in main list and DB
            for (var j = 0; j < idListModelImages.count; j++) {
                if (idListModelImages.get(j).album === oldAlbumName) {
                    idListModelImages.setProperty(j, "album", text)
                    storageItem.addAlbum(idListModelImages.get(j).filePath, text)

                    // save info to IPTC tag if available and wanted
                     if (metadataActive !== 0) {
                        if ( text !== standardAlbum) {
                            py.insertMetadataKeywords ( text, idListModelImages.get(j).filePath )
                        }
                        else {
                            py.removeMetadataKeywords ( idListModelImages.get(j).filePath )
                        }
                    }
                }
            }

            // update favouritesModel as well
            if (idListModelFavourites.count > 0) {
                for ( var k = 0; k < idListModelFavourites.count; k++) {
                    if (idListModelFavourites.get(k).album === oldAlbumName) {
                        //console.log("found it in favourites: " + idListModelFavourites.get(k).filePath)
                        idListModelFavourites.setProperty(k, "album", text)
                    }
                }
            }

            // update searchModel as well
            if (idListModelSearch.count > 0) {
                for ( k = 0; k < idListModelSearch.count; k++) {
                    if (idListModelSearch.get(k).album === oldAlbumName) {
                        //console.log("found it in search: " + idListModelSearch.get(k).filePath)
                        idListModelSearch.setProperty(k, "album", text)
                    }
                }
            }

            if (idListModelSearch.count < 1) {
                countDistinctAlbums( "standard" )
            }
            else {
                countDistinctAlbums( "fromSearch" )
            }
        }
    }

}

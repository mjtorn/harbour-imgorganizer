import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupGif
    z: 10
    width: parent.width
    height: parent.height
    opacity: 0.0
    visible: opacity > 0
    onClicked: {
        hide()
    }

    property var gifPathsArray : []
    property string gifTargetAlbum : ""
    property string gifStep : "fields" // "fields" first, accept switches to the "folder" choice, closing anywhere aborts

    ListModel {
        id: idListModelGifFolders
    }

    Behavior on opacity {
        //FadeAnimator {}
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
            width: Theme.itemSizeLarge * 3.5
            height: idGifColumn.height
            radius: Theme.paddingLarge
            color: buttonBackgroundColor
            border.width: 2
            border.color: Theme.highlightColor

            Column {
                id: idGifColumn
                width: parent.width
                spacing: Theme.paddingSmall

                Item {
                    visible: gifStep === "fields"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width / 3 * 2
                    height: Theme.itemSizeLarge

                    TextField {
                        id: idTextFieldGifName
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        label: qsTr("file name")
                        inputMethodHints: Qt.ImhNoPredictiveText
                        EnterKey.onClicked: {
                            focus = false
                        }
                    }
                }
                Item {
                    visible: gifStep === "fields"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width / 3 * 2
                    height: Theme.itemSizeLarge

                    TextField {
                        id: idTextFieldGifDuration
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        label: qsTr("ms")
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 20; top: 60000 }
                        EnterKey.onClicked: {
                            focus = false
                        }
                    }
                }

                // step two: picking the destination folder is the confirming action
                ListView {
                    visible: gifStep === "folder"
                    width: parent.width
                    height: (gifStep === "folder") ? contentHeight : 0

                    model: idListModelGifFolders
                    delegate: ListItem {
                        contentX: idBackgroundRect.radius
                        contentWidth: parent.width - 2* contentX
                        contentHeight: Theme.itemSizeExtraSmall
                        onClicked: {
                            var gifName = idTextFieldGifName.text
                            if (gifName.toLowerCase().slice(-4) !== ".gif") {
                                gifName = gifName + ".gif"
                            }
                            pendingGifAlbum = gifTargetAlbum
                            finishedLoading = false
                            py.createAnimatedGif( gifPathsArray, Math.round(idTextFieldGifDuration.text, 0), storageMedia, folderPath, gifName )
                            hide()
                        }
                        Label {
                            width: parent.width
                            elide: Text.ElideLeft // a source folder is a full path, its tail is the telling half
                            horizontalAlignment: Text.AlignHCenter
                            text: (storageMedia === "$CURRENT") ? folderPath
                                  : ((storageMedia === "$HOME") ? folderPath : (folderPath + " (SD " + storageMedia + ")"))
                            color: enabled ? Theme.primaryColor : Theme.secondaryColor
                            font.italic: (storageMedia === "$CURRENT") // same note as the rename banner: not a configured folder
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: Theme.paddingLarge
                }
            }
            IconButton {
                anchors.verticalCenter: idGifColumn.verticalCenter
                anchors.horizontalCenter: idGifColumn.left
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-cancel?"
                onClicked: {
                    hide()
                }

                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width / 5*4
                    height: width
                    radius: width/2
                    color: buttonBackgroundColor
                    border.width: 2
                    border.color: Theme.highlightColor
                }
            }
            IconButton {
                visible: gifStep === "fields"
                anchors.verticalCenter: idGifColumn.verticalCenter
                anchors.horizontalCenter: idGifColumn.right
                // no focus gating here: the field text is readable while the keyboard is still up, and a
                // disabled button plus a tap on the backdrop to close the keyboard would silently abort
                enabled: (idTextFieldGifName.text.length > 0) && (idTextFieldGifDuration.text.length > 0)
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-accept?"
                onClicked: {
                    idTextFieldGifName.focus = false
                    idTextFieldGifDuration.focus = false
                    gifStep = "folder"
                }

                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width / 5*4
                    height: width
                    radius: width/2
                    color: buttonBackgroundColor
                    border.width: 2
                    border.color: Theme.highlightColor
                }
            }
        }
    }


    function notify( chosenPathsArray, targetAlbum ) {
        gifPathsArray = chosenPathsArray
        gifTargetAlbum = targetAlbum
        idTextFieldGifName.text = ""
        idTextFieldGifDuration.text = "500"
        gifStep = "fields"
        idTextFieldGifName.focus = true
        idTextFieldGifName.forceActiveFocus()

        // the folders the frames themselves live in come first: that is where the result belongs most
        // often, and it may not be a configured scan folder at all
        idListModelGifFolders.clear()
        var seenSourceFolders = ({})
        for (var s = 0; s < gifPathsArray.length; s++) {
            var sourcePath = (gifPathsArray[s]).toString()
            var sourceFolder = sourcePath.substring(0, sourcePath.lastIndexOf("/"))
            if (sourceFolder !== "" && seenSourceFolders[sourceFolder] !== true) {
                seenSourceFolders[sourceFolder] = true
                idListModelGifFolders.append({ "folderPath" : sourceFolder, "storageMedia" : "$CURRENT" })
            }
        }

        // then the configured scan folders, parsed like the settings page does
        var folders2scanHOME = (storageItem.getSetting("infoFolders2scanHOME", "/Downloads|||/Pictures|||/Documents|||/android_storage")).split("|||")
        for (var i = 0; i < folders2scanHOME.length; i++) {
            if (folders2scanHOME[i] !== "") {
                idListModelGifFolders.append({ "folderPath" : folders2scanHOME[i], "storageMedia" : "$HOME" })
            }
        }
        if (amountExtPartitions !== 0) {
            var folders2scanEXTERN = (storageItem.getSetting("infoFolders2scanEXTERN", "")).split("|||")
            var sdCards2scanEXTERN = (storageItem.getSetting("sdCards2scanEXTERN", "")).split("|||")
            for (var j = 0; j < folders2scanEXTERN.length; j++) {
                if (folders2scanEXTERN[j] !== "" && sdCards2scanEXTERN[j] !== undefined && sdCards2scanEXTERN[j] !== "") {
                    idListModelGifFolders.append({ "folderPath" : folders2scanEXTERN[j], "storageMedia" : sdCards2scanEXTERN[j] })
                }
            }
        }

        popupGif.opacity = 1.0
    }

    function hide() {
        idTextFieldGifName.focus = false
        idTextFieldGifDuration.focus = false
        popupGif.opacity = 0.0
        unselectAll()
    }
}

import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupRenameFile
    z: 10
    width: parent.width
    height: parent.height
    opacity: 0.0
    visible: opacity > 0
    onClicked: {
        hide()
    }

    property string renameImagePath : ""
    property string renameOriginalName : ""
    property string renameStep : "fields" // "fields" first, accept switches to the "folder" choice, closing anywhere aborts

    ListModel {
        id: idListModelRenameFolders
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
            height: idRenameColumn.height
            radius: Theme.paddingLarge
            color: buttonBackgroundColor
            border.width: 2
            border.color: Theme.highlightColor

            Column {
                id: idRenameColumn
                width: parent.width
                spacing: Theme.paddingSmall

                Item {
                    visible: renameStep === "fields"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width / 3 * 2
                    height: Theme.itemSizeLarge

                    TextField {
                        id: idTextFieldRenameName
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

                // step two: picking the destination folder is the confirming action
                ListView {
                    visible: renameStep === "folder"
                    width: parent.width
                    height: (renameStep === "folder") ? contentHeight : 0

                    model: idListModelRenameFolders
                    delegate: ListItem {
                        contentX: idBackgroundRect.radius
                        contentWidth: parent.width - 2* contentX
                        contentHeight: Theme.itemSizeExtraSmall
                        onClicked: {
                            py.renameImageFile( renameImagePath, storageMedia, folderPath, wantedFileName() )
                            hide()
                        }
                        Label {
                            text: (storageMedia === "$CURRENT") ? qsTr("Current directory")
                                  : ((storageMedia === "$HOME") ? folderPath : (folderPath + " (SD " + storageMedia + ")"))
                            color: Theme.primaryColor
                            font.italic: (storageMedia === "$CURRENT")
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: Theme.paddingLarge
                }
            }
            IconButton {
                anchors.verticalCenter: idRenameColumn.verticalCenter
                anchors.horizontalCenter: idRenameColumn.left
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
                visible: renameStep === "fields"
                // no focus gating, the field text is readable while the keyboard is still up
                enabled: nameIsValid()
                anchors.verticalCenter: idRenameColumn.verticalCenter
                anchors.horizontalCenter: idRenameColumn.right
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-accept?"
                onClicked: {
                    idTextFieldRenameName.focus = false
                    renameStep = "folder"
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


    function cleanedFileName() {
        // a name with a path separator would land somewhere else entirely, a leading dot hides the file from the scan
        var typedName = (idTextFieldRenameName.text).replace(/^\s+|\s+$/g, "")
        while (typedName.length > 0 && typedName[0] === ".") {
            typedName = typedName.substring(1)
        }
        return typedName
    }

    function nameIsValid() {
        var typedName = cleanedFileName()
        return (typedName.length > 0) && (typedName.indexOf("/") === -1)
    }

    function wantedFileName() {
        // the original extension is always kept, renaming a jpg into something else would drop it out of every scan
        var wantedName = cleanedFileName()
        var dotIndex = renameOriginalName.lastIndexOf(".")
        if (dotIndex > 0) {
            var originalExtension = renameOriginalName.substring(dotIndex)
            if ((wantedName.toLowerCase()).slice(-originalExtension.length) !== originalExtension.toLowerCase()) {
                wantedName = wantedName + originalExtension
            }
        }
        return wantedName
    }

    function notify( imagePath, imageFileName ) {
        renameImagePath = imagePath
        renameOriginalName = imageFileName
        renameStep = "fields"
        idTextFieldRenameName.text = imageFileName
        idTextFieldRenameName.focus = true
        idTextFieldRenameName.forceActiveFocus()
        // typing replaces the name while the extension stays visible
        var dotIndex = imageFileName.lastIndexOf(".")
        idTextFieldRenameName.select(0, (dotIndex > 0) ? dotIndex : imageFileName.length)

        // the current directory first, it may be a subfolder that is not a scan folder itself
        idListModelRenameFolders.clear()
        idListModelRenameFolders.append({ "folderPath" : "", "storageMedia" : "$CURRENT" })
        var folders2scanHOME = (storageItem.getSetting("infoFolders2scanHOME", "/Downloads|||/Pictures|||/Documents|||/android_storage")).split("|||")
        for (var i = 0; i < folders2scanHOME.length; i++) {
            if (folders2scanHOME[i] !== "") {
                idListModelRenameFolders.append({ "folderPath" : folders2scanHOME[i], "storageMedia" : "$HOME" })
            }
        }
        if (amountExtPartitions !== 0) {
            var folders2scanEXTERN = (storageItem.getSetting("infoFolders2scanEXTERN", "")).split("|||")
            var sdCards2scanEXTERN = (storageItem.getSetting("sdCards2scanEXTERN", "")).split("|||")
            for (var j = 0; j < folders2scanEXTERN.length; j++) {
                if (folders2scanEXTERN[j] !== "" && sdCards2scanEXTERN[j] !== undefined && sdCards2scanEXTERN[j] !== "") {
                    idListModelRenameFolders.append({ "folderPath" : folders2scanEXTERN[j], "storageMedia" : sdCards2scanEXTERN[j] })
                }
            }
        }

        popupRenameFile.opacity = 1.0
    }

    function hide() {
        idTextFieldRenameName.focus = false
        popupRenameFile.opacity = 0.0
    }
}

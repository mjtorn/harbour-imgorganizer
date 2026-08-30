import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupFixFileType
    z: 10
    width: parent.width
    height: parent.height
    opacity: 0.0
    visible: opacity > 0
    onClicked: {
        if (waitingForRemorse === true) { return } // the countdown owns the screen until it is done
        hide() // closing changes nothing on disk, only the accept button may
    }

    property bool waitingForRemorse : false // a delete is counting down, this panel must stay visible for it
    property string troubleImagePath : ""
    property string troubleReason : ""
    property string troubleRealKind : ""
    property string troubleSuggestedName : ""
    property real troubleFileSize : 0
    property string troubleFromPage : ""

    RemorsePopup {
        // lives inside this panel, so the panel may not go invisible while the countdown runs
        height: Theme.itemSizeLarge * 1.3
        id: remorseFixFileType
        onCanceled: {
            waitingForRemorse = false
            hide() // called off, the file is untouched
        }
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
            width: parent.width - 2*Theme.paddingLarge
            height: idFixColumn.height + 2*Theme.paddingLarge
            radius: Theme.paddingLarge
            color: buttonBackgroundColor
            border.width: 2
            border.color: Theme.highlightColor

            Column {
                id: idFixColumn
                anchors.centerIn: parent
                width: parent.width - Theme.itemSizeLarge * 2.6
                spacing: Theme.paddingMedium

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: (troubleReason === "wrongExtension")
                          ? qsTr("This is a %1 file with a wrong name").arg(troubleRealKind.toUpperCase())
                          : qsTr("No decoder can read this file")
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    text: (troubleReason === "wrongExtension")
                          ? qsTr("Rename it to %1 so every app can show it").arg(troubleSuggestedName)
                          : qsTr("Delete it? It is %1 kB and shows up empty everywhere").arg(Math.round(troubleFileSize / 1024))
                }
            }
            IconButton {
                anchors.verticalCenter: idFixColumn.verticalCenter
                anchors.horizontalCenter: idBackgroundRect.left
                anchors.horizontalCenterOffset: Theme.itemSizeLarge * 0.8
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-cancel?"
                onClicked: {
                    hide() // closing changes nothing on disk, only the accept button may
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
                anchors.verticalCenter: idFixColumn.verticalCenter
                anchors.horizontalCenter: idBackgroundRect.right
                anchors.horizontalCenterOffset: -Theme.itemSizeLarge * 0.8
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-accept?"
                onClicked: {
                    if (troubleReason === "wrongExtension") {
                        // the rename path carries the album, the favourite and both cache entries over
                        py.renameImageFile( troubleImagePath, "$CURRENT", "", troubleSuggestedName )
                    }
                    else {
                        // deleting cannot be undone, so it waits behind the usual remorse
                        var doomedPath = troubleImagePath
                        var doomedFromPage = troubleFromPage
                        waitingForRemorse = true
                        remorseFixFileType.execute( qsTr("Delete file?"), function() {
                            waitingForRemorse = false
                            deleteThisImage( [ doomedPath ], doomedFromPage )
                            hide()
                        })
                        return // the panel stays up, otherwise the countdown would be invisible and uncancellable
                    }
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
        }
    }


    function notify( imagePath, reason, realKind, suggestedName, fileSize, fromPage ) {
        troubleImagePath = imagePath
        troubleReason = reason
        troubleRealKind = realKind
        troubleSuggestedName = suggestedName
        troubleFileSize = fileSize
        troubleFromPage = fromPage
        waitingForRemorse = false
        popupFixFileType.opacity = 1.0
    }

    function hide() {
        // deliberately side effect free: the backdrop tap, the cancel button and a swipe all land here
        popupFixFileType.opacity = 0.0
    }
}

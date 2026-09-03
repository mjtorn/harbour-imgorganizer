import QtQuick 2.6
import Sailfish.Silica 1.0


MouseArea {
    id: popupRebuildHashes
    z: 10
    width: parent.width
    height: parent.height
    opacity: 0.0
    visible: opacity > 0
    onClicked: {
        hide() // turning it down costs nothing, the old duplicates stay on screen
    }

    property int rebuildImageCount : 0

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
            height: idRebuildColumn.height + 2*Theme.paddingLarge
            radius: Theme.paddingLarge
            color: buttonBackgroundColor
            border.width: 2
            border.color: Theme.highlightColor

            Column {
                id: idRebuildColumn
                anchors.centerIn: parent
                width: parent.width - Theme.itemSizeLarge * 2.6
                spacing: Theme.paddingMedium

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: qsTr("Duplicate matching improved")
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    // the old fingerprints measured something else, so they cannot be carried over
                    text: qsTr("This reads %1 images once more, a few minutes. Later searches are fast again.").arg(rebuildImageCount)
                }
            }
            IconButton {
                anchors.verticalCenter: idRebuildColumn.verticalCenter
                anchors.horizontalCenter: idBackgroundRect.left
                anchors.horizontalCenterOffset: Theme.itemSizeLarge * 0.8
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-cancel?"
                onClicked: {
                    hide() // no rebuild, so no duplicate search either - the offer returns next time
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
                anchors.verticalCenter: idRebuildColumn.verticalCenter
                anchors.horizontalCenter: idBackgroundRect.right
                anchors.horizontalCenterOffset: -Theme.itemSizeLarge * 0.8
                height: Theme.itemSizeLarge * 1.1
                width: height
                icon.scale: 1
                icon.source: "image://theme/icon-m-accept?"
                onClicked: {
                    hide()
                    runDuplicateSearch( true ) // the same search again, this time allowed to rebuild
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


    function notify( imageCount ) {
        rebuildImageCount = imageCount
        popupRebuildHashes.opacity = 1.0
    }

    function hide() {
        popupRebuildHashes.opacity = 0.0
    }
}

import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Notifications 1.0 // for the urgency enum, the notification itself comes from FirstPage


Page {
    id: page
    allowedOrientations: Orientation.Portrait //All

    // get from page before
    property var exifList
    property var availableExifInfosList
    property var filePath
    property var fileName
    property var folderPath
    property var creationDateMS
    property var estimatedSize
    property var album
    property var imageWidth
    property var imageHeight
    property var timestampSource
    property var isFavourite

    // own variables
    property var excludeEditTags : ["IPTC Keywords"]

    Component.onCompleted: {
        function msToDate( inputMS ) {
            return new Date (inputMS*1000)
        }
        idListModelMetaInfo.clear()
        idListModelMetaInfo.append({ "tagName" : "Name",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : fileName.toString(),
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Folder",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : folderPath.toString(),
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "File Created",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : msToDate(creationDateMS).toString(),
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Created Date Source",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : timestampSource,
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Size",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : estimatedSize.toString() + " MB",
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Width",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : imageWidth.toString() + " px",
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Height",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : imageHeight.toString() + " px",
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Album",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : album.toString(),
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : "Favourite",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : isFavourite.toString(),
                                    "tagEditable" : false
                                   })
        idListModelMetaInfo.append({ "tagName" : " ",
                                    "tag_nr" : 0,
                                    "ifd_zone" : "none",
                                    "tagValue" : " ",
                                    "tagEditable" : false
                                   })
        for(var i = 0; i < exifList.length; i++) {
            var currentTagName = (exifList[i][0]).toString()
            for(var j = 0; j < excludeEditTags.length; j++) {
                if (currentTagName !== excludeEditTags[j]) {
                    var reallyEditable = true
                }
                else {
                    reallyEditable = false
                }
            }
            idListModelMetaInfo.append({
                                        "tagName" : currentTagName,
                                        "tag_nr" : (exifList[i][2] !== undefined) ? parseInt(exifList[i][2]) : 0,
                                        "ifd_zone" : (exifList[i][3] !== undefined) ? (exifList[i][3]).toString() : "none",
                                        "tagValue" : (exifList[i][1] !== undefined) ? (exifList[i][1]).toString() : "none", // (exifList[i][1]).toString(),
                                        "tagEditable" : reallyEditable
                                     })
        }
    }

    BannerEditMeta {
        id: bannerEditMeta
    }
    ListModel {
        id: idListModelMetaInfo
    }


    SilicaFlickable {
        id: listView
        anchors.fill: parent
        contentHeight: idColumn.height  // Tell SilicaFlickable the height of its content.

        PullDownMenu {
            quickSelect: true

            MenuItem {
                text: qsTr("Copy location")
                onClicked: {
                    Clipboard.text = (filePath).toString()
                    // the notification object lives on FirstPage and is shared, so set every field before publishing
                    idNotificationEditSaved.isTransient = true
                    idNotificationEditSaved.urgency = Notification.Low
                    idNotificationEditSaved.summary = ""
                    idNotificationEditSaved.body = ""
                    idNotificationEditSaved.previewSummary = qsTr("Location copied")
                    idNotificationEditSaved.previewBody = fileName
                    idNotificationEditSaved.publish()
                }
            }
        }
        VerticalScrollDecorator {}

        Column {
            id: idColumn
            width: parent.width

            Label {
                width: parent.width
                height: Theme.itemSizeLarge
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.primaryColor
                text: qsTr("Details & Metadata")
            }
            Repeater {
                x: Theme.paddingLarge
                width: idColumn.width - 2*x
                model: idListModelMetaInfo

                Row {
                    width: idColumn.width
                    spacing: Theme.paddingLarge
                    bottomPadding: Theme.paddingMedium

                    Label {
                        width: parent.width/2 - parent.spacing/2
                        font.pixelSize: Theme.fontSizeExtraSmall
                        //color: Theme.secondaryHighlightColor
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        text: tagName
                    }
                    Label {
                        width: parent.width/2 - parent.spacing/2
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: (tagEditable && infoStrictReadOnly === 0) ? Theme.highlightColor : Theme.secondaryColor
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        text: tagValue

                        MouseArea {
                            anchors.fill: parent
                            //onPressAndHold: {
                            onClicked: {
                                if (tagEditable && infoStrictReadOnly === 0) { // strict read-only mode never writes into image files
                                    bannerEditMeta.notify( Theme.highlightDimmerColor, filePath, ifd_zone, tag_nr, tagName, tagValue, index )
                                }
                            }
                        }
                    }


                }
            }
            Item {
                width: parent.width
                height: Theme.itemSizeMedium
            }
        }
    }
}

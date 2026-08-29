#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pyotherside
import os
import datetime
import re
import glob
from pathlib import Path            # for finding $HOME directory path
from operator import itemgetter     # for sorting a list of tuples by given item-index
import iptcinfo3                    # standalone IPTC metadata
import piexif                       # standalone EXIF metadata
import piexif.helper
import subprocess                   # for running shell commands as separate processes
import zipfile                      # for sharing multiple files at once, e.g. on bluetooth
import pickle                       # for caching exif scan results between app starts
import shutil                       # for moving files across filesystems, e.g. onto an sd card
try:
    import PIL
    try:
        version = float((PIL.__version__).split(".")[0])
        if version < 7:
            pyotherside.send('pillowNotAvailable', "tooOld" )
    except:
        pyotherside.send('pillowNotAvailable', "tooOld" )
    from PIL import Image
    from PIL import ImageColor
    from PIL import ImageDraw
    from PIL import ImageOps
    from PIL import ImageEnhance
except ImportError:
    pyotherside.send('pillowNotAvailable', "notInstalled")
#from concurrent.futures import ThreadPoolExecutor   # activates multithreading





# variables, readable
extensions = ('.jpg', '.JPG', '.jpeg', '.JPEG', '.png', '.PNG', '.tif', '.TIF', '.tiff', '.TIFF','.bmp', '.BMP', '.gif', '.GIF')
exifEnabledExtensions = ('.jpg', '.JPG', '.jpeg', '.JPEG', '.tif', '.tiff', '.TIF', '.TIFF')
iptcEnabledExtensions = ('.jpg', '.JPG', '.jpeg', '.JPEG')
exifCacheVersion = 1                # bump when the cached tuple layout changes -> forces a clean cache rebuild
dHashCacheVersion = 1               # bump when the perceptual hash layout changes -> forces a clean cache rebuild





# image editing: general file checks if metadata can be saved
def bool_canSaveWithExif ( filePath ):
    if filePath.endswith( exifEnabledExtensions ):
        file_modificationDateMS = os.path.getmtime(filePath)
        timeUTC_object_created = datetime.datetime.utcfromtimestamp(file_modificationDateMS)
        creationDateMS_string = timeUTC_object_created.strftime('%Y:%m:%d %H:%M:%S')
        try:
            exif_dict = piexif.load(filePath)
            # remove the orientation EXIF tag, otherwise some images will be falsely rotated
            exif_dict["0th"][274] = ("").encode()
            # check for datetime in exif - if not, paste this datetime into EXIF, e.g. img without datetime gets rotated by pillow and saves as a new image but keeps correct timestamp
            try:
                if (piexif.ImageIFD.DateTime not in exif_dict["0th"]) and (piexif.ExifIFD.DateTimeOriginal not in exif_dict["Exif"]):
                    pyotherside.send('debugPythonLogs', "No EXIF datetime available, writing creationdate instead." )
                    exif_dict["0th"][piexif.ImageIFD.DateTime] = (creationDateMS_string).encode()
            except:
                pyotherside.send('debugPythonLogs', "Error inserting exif datetime, but life goes on." )
            # store as bytes
            exif_bytes = piexif.dump(exif_dict)
            if exif_bytes is None:
                saveWithExif = False
                exif_bytes = 0
            else:
                saveWithExif = True
        except:
            saveWithExif = False
            exif_bytes = 0
    else:
        saveWithExif = False
        exif_bytes = 0
    return saveWithExif, exif_bytes


def bool_canSaveWithIPTC( filePath ):
    iptc_keywords = []
    if filePath.endswith( iptcEnabledExtensions ):
        try:
            iptc_info = iptcinfo3.IPTCInfo(filePath)
            if iptc_info is None:
                saveWithIPTC = False
                iptc_info = 0
            else:
                saveWithIPTC = True
        except:
            saveWithIPTC = False
            iptc_info = 0
    else:
        saveWithIPTC = False
        iptc_info = 0
    return saveWithIPTC, iptc_info


def createAnimatedGif ( gifPathList, frameDurationMS, targetStorageMedia, targetFolder, gifFileName ):
    # canvas is the largest frame, smaller frames get scaled up to fit and centered - the source images are only ever read
    try:
        # resolve the chosen scan folder the same way scanForImages does, except for a folder one of
        # the frames came from, which arrives as the absolute path it already is
        if "$CURRENT" in targetStorageMedia:
            targetPath = targetFolder + "/" + gifFileName
        elif "$HOME" in targetStorageMedia:
            targetPath = str(Path.home()) + targetFolder + "/" + gifFileName
        else:
            targetPath = str((glob.glob("/run/media/*/*"))[int(targetStorageMedia)-1]) + targetFolder + "/" + gifFileName

        canvasWidth = 0
        canvasHeight = 0
        for filePath in gifPathList:
            img = Image.open(filePath)
            img = ImageOps.exif_transpose(img)
            if img.size[0] > canvasWidth:
                canvasWidth = img.size[0]
            if img.size[1] > canvasHeight:
                canvasHeight = img.size[1]
            img.close()

        # never overwrite an existing file
        dotIndex = targetPath.rfind(".")
        basePath = targetPath[:dotIndex]
        extension = targetPath[dotIndex:]
        copyNumber = 2
        while os.path.exists(targetPath):
            targetPath = basePath + str(copyNumber) + extension
            copyNumber += 1

        def buildGifFrame ( filePath ):
            img = Image.open(filePath)
            img = ImageOps.exif_transpose(img)
            if img.mode != 'RGB':
                img = img.convert('RGB')
            scaleFactor = min(canvasWidth / img.size[0], canvasHeight / img.size[1])
            scaledImg = img.resize( (int(img.size[0] * scaleFactor), int(img.size[1] * scaleFactor)), Image.LANCZOS )
            frame = Image.new('RGB', (canvasWidth, canvasHeight), (0, 0, 0))
            frame.paste( scaledImg, ( (canvasWidth - scaledImg.size[0]) // 2, (canvasHeight - scaledImg.size[1]) // 2 ) )
            img.close()
            return frame

        # a generator keeps only one frame in memory at a time
        def remainingGifFrames():
            for frameNumber in range(1, len(gifPathList)):
                pyotherside.send('scanProgress', frameNumber + 1, len(gifPathList))
                yield buildGifFrame(gifPathList[frameNumber])

        pyotherside.send('scanProgress', 1, len(gifPathList))
        firstFrame = buildGifFrame(gifPathList[0])
        firstFrame.save(targetPath, save_all=True, append_images=remainingGifFrames(), duration=int(frameDurationMS), loop=0)
        firstFrame.close()
        pyotherside.send('gifCreated', targetPath)
    except: # anything failed -> QML shows nothing new, no source image was written to either way
        pyotherside.send('gifCreated', "")


def buildEditedCopyPath ( filePath ):
    dotIndex = filePath.rfind(".")
    copyPath = filePath[:dotIndex] + "_edited" + filePath[dotIndex:]
    copyNumber = 2
    while os.path.exists(copyPath):
        copyPath = filePath[:dotIndex] + "_edited" + str(copyNumber) + filePath[dotIndex:]
        copyNumber += 1
    return copyPath


def saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info ):
    # edits never touch the original, the result is always saved as a new copy next to it
    copyPath = buildEditedCopyPath( filePath )
    if saveWithExif is True:
        output_img.save(copyPath, compress_level=1, exif=exif_bytes)
    else:
        output_img.save(copyPath, compress_level=1)
    if saveWithIPTC is True:
        # carry the IPTC keywords over onto the copy - iptc_info.save_as would clobber the copy with the original's pixel data
        try:
            iptc_copy = iptcinfo3.IPTCInfo( copyPath, force=True )
            iptc_copy['keywords'] = iptc_info['keywords']
            iptc_copy.save()
        except: # keywords also live in the DB, losing them inside the copy is not fatal
            pass
    pyotherside.send('updateImage', )
    pyotherside.send('editedImageSaved', copyPath)
    return copyPath



# image editing functions  with pillow
def imageRotateFunction ( filePath, targetAngle ):
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    output_img = img.rotate(int(targetAngle), expand = True) # 90=left / 270=right
    saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()
    output_img.close()


def imageFlipMirrorFunction ( filePath, targetDirection ):
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    if "vertical" in targetDirection:
        output_img = ImageOps.flip(img)
    else: # "horizontal"
        output_img = ImageOps.mirror(img)
    saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()
    output_img.close()


def imageCropFunction ( filePath, rectX, rectY, rectWidth, rectHeight, scaleFactor ):
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    rectX_real = int(rectX * scaleFactor)
    rectY_real = int(rectY * scaleFactor)
    rectWidth_real = int(rectWidth * scaleFactor)
    rectHeight_real = int(rectHeight * scaleFactor)
    area = (rectX_real, rectY_real, rectX_real+rectWidth_real, rectY_real+rectHeight_real)
    output_img = img.crop(area)
    copyPath = saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()
    output_img.close()
    newFileSize = os.stat(copyPath).st_size
    pyotherside.send('updateSingleFileSize', copyPath, newFileSize )


def imageColorizeFunction ( filePath, brightnessFactor, contrastFactor ):
    brightnessFactor = float(brightnessFactor) + 1
    contrastFactor = float(contrastFactor) + 1
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    if img.mode not in ('RGBA'):
        img = img.convert('RGBA')
    if brightnessFactor != 1:
        output_img_brightness = ImageEnhance.Brightness(img)
        output_img_brightness = output_img_brightness.enhance(brightnessFactor)
    else:
        output_img_brightness = img
    if contrastFactor != 1:
        output_img = ImageEnhance.Contrast(output_img_brightness)
        output_img = output_img.enhance(contrastFactor)
    else:
        output_img = output_img_brightness
    saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()
    output_img.close()


def imageResizeFunction ( filePath, targetWidth, targetHeight ):
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    output_img = img.resize( (int(targetWidth), int(targetHeight)), Image.ANTIALIAS )
    copyPath = saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()
    output_img.close()
    pyotherside.send('batchResizeProgress', 100)
    newFileSize = os.stat(copyPath).st_size
    pyotherside.send('updateSingleFileSize', copyPath, newFileSize )

def imageBulkResizeFunction ( imagePathsList, targetWidth, targetHeight, targetDirection ):
    allfilePathList = []
    allfilePathList = imagePathsList.split("|||")
    amountFiles = len(allfilePathList)
    progressCounter = 0
    for filePath in allfilePathList:
        if len(filePath) > 0: # make sure that file actually exists
            img = Image.open(filePath)
            saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
            saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
            img = ImageOps.exif_transpose(img)
            if "preferWidth" in targetDirection:
                baseWidth = int(targetWidth)
                widthPercent = (baseWidth/float(img.size[0]))
                propHeight = int((float(img.size[1])*float(widthPercent)))
                output_img = img.resize( (baseWidth, propHeight), Image.ANTIALIAS )
            else:
                baseHeight = int(targetHeight)
                heightPercent = (baseHeight/float(img.size[1]))
                propWidth = int((float(img.size[0])*float(heightPercent)))
                output_img = img.resize( (propWidth, baseHeight), Image.ANTIALIAS )
            copyPath = saveEditedImage ( output_img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
            img.close()
            output_img.close()

            newFileSize = os.stat(copyPath).st_size
            pyotherside.send('updateSingleFileSize', copyPath, newFileSize )
            progressCounter += 1
            progressResizing = progressCounter / amountFiles * 100
            pyotherside.send('batchResizeProgress', progressResizing)

def imagePaintFunction ( filePath, scaleFactor, freeDrawPolyCoordinatesArray, lineColorArray, lineWidthArray ):
    img = Image.open(filePath)
    saveWithExif, exif_bytes = bool_canSaveWithExif( filePath )
    saveWithIPTC, iptc_info = bool_canSaveWithIPTC( filePath )
    img = ImageOps.exif_transpose(img)
    draw = ImageDraw.Draw(img)
    for i in range (0, len(freeDrawPolyCoordinatesArray)) :
        coordinatesList = list( freeDrawPolyCoordinatesArray[i].split(";") )
        lineWidth = int( float(lineWidthArray[i]) * float(scaleFactor) )
        lineColor = ImageColor.getrgb(lineColorArray[i])
        del coordinatesList[-1] # remove last comma
        coordinatesList = list(map(float, coordinatesList))
        coordinatesList = [i * float(scaleFactor) for i in coordinatesList]
        pairSublist = []
        fullPairsList = []
        for i in range(0, len(coordinatesList)-1, 2):
            pairSublist.append ( coordinatesList[i] )
            pairSublist.append ( coordinatesList[i+1] )
            fullPairsList.append ( tuple(pairSublist) )
            pairSublist.clear()
        coordinatesTuples = tuple(fullPairsList)
        draw.line( (coordinatesTuples), fill = lineColor, width = lineWidth, joint = 'curve')
    saveEditedImage ( img, filePath, saveWithExif, exif_bytes, saveWithIPTC, iptc_info )
    img.close()



# general organizing functions
def scanForImages (folders2scanHOME, folders2scanEXTERN, sdCards2scanEXTERN, showDirection, creationModificationDate, showHiddenFiles, findExifAlbum):
    dirsToScan = []
    homeDir = str(Path.home())

    # remove possible tmp files
    tempPath = homeDir + "/Downloads/" + "ImgOrganizer.zip"
    if os.path.exists(tempPath):
        os.remove(tempPath)

    #if folders2scanHOME[0] is not "":
    if folders2scanHOME[0] != "":
        for folders in folders2scanHOME:
            folderPath = homeDir + folders
            if os.path.exists(folderPath):
                dirsToScan.append(folderPath)

    #convert numeric sdCards2scanEXTERN to a full path
    #if sdCards2scanEXTERN[0] is not "":
    if sdCards2scanEXTERN[0] != "":
        extCardPathsToScan = []
        if len(glob.glob("/run/media/*/*")) != 0:
            for cardNumber in sdCards2scanEXTERN:
                sdCardPath = str((glob.glob("/run/media/*/*"))[int(cardNumber)-1])
                extCardPathsToScan.append (sdCardPath)
        else:
            extCardPathsToScan.append ("/run/media")

        helperCounter = 0
        for folders in folders2scanEXTERN:
            folderPath = extCardPathsToScan[helperCounter] + folders
            #pyotherside.send('debugPythonLogs', folderPath)
            helperCounter = helperCounter + 1
            if os.path.exists(folderPath):
                dirsToScan.append(folderPath)

    # no dublicates in folders
    dirsToScan = [i for n, i in enumerate(dirsToScan) if i not in dirsToScan[:n]]

    # now get all files possible in all folders and subfolders
    global someCounter
    someCounter = 0
    filteredFilePathList = []
    for folder in dirsToScan:
        #pyotherside.send('debugPythonLogs', folder)
        for dirPath, dirNames, fileNames in os.walk(folder):
            if showHiddenFiles == 0: # exclude hidden files and folders
                fileNames = [f for f in fileNames if not f[0] == '.']
                dirNames[:] = [d for d in dirNames if not d[0] == '.']
            fileNames = [f for f in fileNames if f.endswith( extensions )]
            for f in fileNames:
                filePath = dirPath + os.sep + f
                if (".thumbnail" not in filePath and "?" not in filePath and "*" not in filePath):
                    filteredFilePathList.append( filePath )
                    #pyotherside.send('debugPythonLogs', filePath)
    #filteredFilePathList = [i for n, i in enumerate(filteredFilePathList) if i not in filteredFilePathList[:n]]        # no dublicates check, but unnecessary!!!

    # Do not need the total amount here unless debugging
    # imagesTotalAmount = len(filteredFilePathList)
    #pyotherside.send('debugPythonLogs', str(imagesTotalAmount) + " images found")

    # save some memory
    dirsToScan = []
    extCardPathsToScan = []

    fileInfoList = getFileInfoList(filteredFilePathList, showDirection, creationModificationDate, findExifAlbum)
    return fileInfoList


def getFileInfoList(filteredFilePathList, showDirection, creationModificationDate, findExifAlbum):
    fileInfoList = scanExifs(filteredFilePathList, creationModificationDate, findExifAlbum)

    # sort according to date time direction
    if "0" in showDirection:
        fileInfoList.sort(key=itemgetter(0), reverse=True) # sort list of tuples by first item, requires import itemgetter
    else:
        fileInfoList.sort(key=itemgetter(0), reverse=False) # sort list of tuples by first item, requires import itemgetter

    # sendentire list over to QML
    pyotherside.send('returnSortedImageList2Model', fileInfoList)

    return fileInfoList


def exifCachePath():
    cacheDir = os.environ.get("XDG_CACHE_HOME", str(Path.home()) + "/.cache") + "/harbour-timeline"
    os.makedirs(cacheDir, exist_ok=True)
    return cacheDir + "/exifCache.pickle"


def dHashCachePath():
    cacheDir = os.environ.get("XDG_CACHE_HOME", str(Path.home()) + "/.cache") + "/harbour-timeline"
    os.makedirs(cacheDir, exist_ok=True)
    return cacheDir + "/dhashCache.pickle"


def buildImageDHash ( filePath ):
    # 64 bit perceptual difference hash, visually identical re-encodes get the same value
    img = Image.open(filePath)
    img.draft('L', (72, 72)) # decodes jpgs at reduced scale, much faster, no-op for other formats
    img = img.convert('L').resize( (9, 8), Image.LANCZOS ) # same filter as ANTIALIAS, the name survives newer pillow versions
    pixelData = list(img.getdata())
    img.close()
    dHash = 0
    for row in range(8):
        for col in range(8):
            dHash = (dHash << 1) | (1 if pixelData[row*9+col] < pixelData[row*9+col+1] else 0)
    return dHash


def findDuplicateImages ( filePathList, tolerance ):
    tolerance = int(tolerance) # qml hands numbers over as floats, and the chunk count below indexes with it
    # load the whole dhash cache once, any load problem -> rebuild from scratch, that keeps the cache clean
    cachedHashDict = {}
    try:
        with open(dHashCachePath(), 'rb') as cacheFile:
            cacheVersion, cachedHashDict = pickle.load(cacheFile)
        if cacheVersion != dHashCacheVersion:
            cachedHashDict = {}
    except:
        cachedHashDict = {}

    imagesTotalAmount = len(filePathList)
    someHashCounter = 0
    hashByPath = {}
    newCacheEntries = {}
    for filePath in filePathList:
        someHashCounter += 1
        if someHashCounter % 25 == 0 or someHashCounter == imagesTotalAmount:
            pyotherside.send('scanProgress', someHashCounter, imagesTotalAmount) # every file would be 24k round trips for nothing
        try:
            statResult = os.stat(filePath)
            if filePath in cachedHashDict and cachedHashDict[filePath][0] == statResult.st_mtime:
                hashByPath[filePath] = cachedHashDict[filePath][1]
            else:
                imageDHash = buildImageDHash( filePath )
                hashByPath[filePath] = imageDHash
                newCacheEntries[filePath] = (statResult.st_mtime, imageDHash)
        except: # unreadable file -> just skip it
            pass

    # add fresh hashes to the cache and drop entries of deleted files
    scannedPathsSet = set(filePathList)
    deadCachePaths = [cachedPath for cachedPath in cachedHashDict if cachedPath not in scannedPathsSet and not os.path.exists(cachedPath)]
    if len(newCacheEntries) > 0 or len(deadCachePaths) > 0:
        for cachedPath in deadCachePaths:
            del cachedHashDict[cachedPath]
        cachedHashDict.update(newCacheEntries)
        try:
            with open(dHashCachePath() + ".tmp", 'wb') as cacheFile:
                pickle.dump( (dHashCacheVersion, cachedHashDict), cacheFile )
            os.replace(dHashCachePath() + ".tmp", dHashCachePath())
        except: # e.g. read-only filesystem -> no cache this time, gets rebuilt on next run
            pass

    # group the hashes: files sharing a hash always belong together, near matching additionally
    # buckets the distinct hashes into tolerance+1 chunks. within a distance of t at most t chunks
    # can carry a differing bit, so at least one chunk has to be identical (pigeonhole) - with
    # fewer chunks than that a pair sitting exactly at the tolerance is never even compared
    pathsByHash = {}
    for filePath in filePathList:
        if filePath in hashByPath:
            pathsByHash.setdefault(hashByPath[filePath], []).append(filePath)

    if tolerance == 0:
        duplicateGroups = [pathGroup for pathGroup in pathsByHash.values() if len(pathGroup) > 1]
    else:
        chunkCount = tolerance + 1
        chunkEdges = [ (chunkIndex * 64) // chunkCount for chunkIndex in range(chunkCount + 1) ]
        candidateBuckets = {}
        for imageDHash in pathsByHash:
            for chunkIndex in range(chunkCount):
                lowBit = chunkEdges[chunkIndex]
                chunkMask = (1 << (chunkEdges[chunkIndex + 1] - lowBit)) - 1
                candidateBuckets.setdefault( (chunkIndex, (imageDHash >> lowBit) & chunkMask), []).append(imageDHash)

        # every verified pair, per distinct hash: a hundred copies of one image are a single hash
        # here, not a hundred entry bucket compared against itself
        matesOfHash = {}
        for bucketHashes in candidateBuckets.values():
            if len(bucketHashes) < 2:
                continue
            for i in range(len(bucketHashes)):
                someHash = bucketHashes[i]
                for j in range(i + 1, len(bucketHashes)):
                    otherHash = bucketHashes[j]
                    if bin(someHash ^ otherHash).count("1") <= tolerance:
                        matesOfHash.setdefault(someHash, set()).add(otherHash)
                        matesOfHash.setdefault(otherHash, set()).add(someHash)

        # a group is a clique: every member within the tolerance of every other member, so the
        # slider means what it says. merging every pair transitively instead would chain - two
        # images four apart from a third but eight from each other would share a group at four -
        # and a chain has no bound at all: at eight it grew one group of 792 images, some of them
        # 55 bits apart. the cost of not chaining is that a hash whose only mates were claimed by
        # earlier groups waits for a later search, once the copies around it are dealt with
        scanOrderOfHash = {}
        for imageDHash in pathsByHash: # insertion ordered, so this is the order the files were scanned in
            scanOrderOfHash[imageDHash] = len(scanOrderOfHash)
        groupedHashSet = set()
        hashGroupList = []
        for imageDHash in pathsByHash:
            if imageDHash in groupedHashSet:
                continue
            hashGroup = [imageDHash]
            # scan order, not set order, so the same library always groups the same way
            for mateHash in sorted(matesOfHash.get(imageDHash, ()), key=lambda someHash: scanOrderOfHash[someHash]):
                if mateHash in groupedHashSet:
                    continue
                fitsAll = True
                for memberHash in hashGroup:
                    if bin(mateHash ^ memberHash).count("1") > tolerance:
                        fitsAll = False
                        break
                if fitsAll is True:
                    hashGroup.append(mateHash)
            # identical files are duplicates of each other whether or not a near neighbour turned up
            if len(hashGroup) > 1 or len(pathsByHash[imageDHash]) > 1:
                hashGroupList.append(hashGroup)
                groupedHashSet.update(hashGroup)

        groupIndexOfHash = {}
        for groupIndex in range(len(hashGroupList)):
            for imageDHash in hashGroupList[groupIndex]:
                groupIndexOfHash[imageDHash] = groupIndex
        pathsByGroupIndex = {}
        for filePath in filePathList:
            if filePath in hashByPath and hashByPath[filePath] in groupIndexOfHash:
                pathsByGroupIndex.setdefault(groupIndexOfHash[hashByPath[filePath]], []).append(filePath)
        duplicateGroups = [pathGroup for pathGroup in pathsByGroupIndex.values() if len(pathGroup) > 1]

    # every group is measured against its own first member, -1 marks that reference image itself.
    # near matching groups by union-find over verified pairs, so a chained member can sit further
    # away than the tolerance - the distance is what makes that visible instead of mysterious
    distanceFromReference = {}
    for pathGroup in duplicateGroups:
        referenceHash = hashByPath[pathGroup[0]]
        distanceFromReference[pathGroup[0]] = -1
        for filePath in pathGroup[1:]:
            distanceFromReference[filePath] = bin(referenceHash ^ hashByPath[filePath]).count("1")

    pyotherside.send('returnDuplicateImages', duplicateGroups, distanceFromReference)


def scanExifs(filteredFilePathList, creationModificationDate, findExifAlbum):
    global someCounter
    someCounter = 0

    imagesTotalAmount = len(filteredFilePathList)

    # scan each file for meta info
    fileInfoList = []

    # load the whole exif cache once, only needed when we scan for meta data
    # any load problem (missing file, corrupt pickle, other python version, changed layout) -> rebuild from scratch, that keeps the cache clean
    cachedExifDict = {}
    if findExifAlbum == 1:
        try:
            with open(exifCachePath(), 'rb') as cacheFile:
                cacheVersion, cachedExifDict = pickle.load(cacheFile)
            if cacheVersion != exifCacheVersion: # cached tuple layout changed in an app update
                cachedExifDict = {}
        except:
            cachedExifDict = {}
        if len(cachedExifDict) == 0 and imagesTotalAmount > 0:
            pyotherside.send('refreshingExifCache')

    newCacheEntries = {}
    for filePath in filteredFilePathList:
        someCounter += 1
        pyotherside.send('scanProgress', someCounter, imagesTotalAmount)
        statResult = os.stat(filePath)
        cachedExifInfo = None
        if filePath in cachedExifDict and cachedExifDict[filePath][0] == statResult.st_mtime:
            cachedExifInfo = (cachedExifDict[filePath][1], cachedExifDict[filePath][2])
        fileInfo = scan4exifInfo(filePath, creationModificationDate, findExifAlbum, statResult, cachedExifInfo)
        fileInfoList.append(fileInfo)
        if findExifAlbum == 1 and cachedExifInfo is None:
            exifTimeMS = fileInfo[0] if fileInfo[7] == "exifMetadata" else 0
            newCacheEntries[filePath] = (statResult.st_mtime, exifTimeMS, fileInfo[6])

    # add fresh scan results to the cache and drop entries of deleted files
    if findExifAlbum == 1:
        scannedPathsSet = set(filteredFilePathList)
        deadCachePaths = [cachedPath for cachedPath in cachedExifDict if cachedPath not in scannedPathsSet and not os.path.exists(cachedPath)]
        if len(newCacheEntries) > 0 or len(deadCachePaths) > 0:
            for cachedPath in deadCachePaths:
                del cachedExifDict[cachedPath]
            cachedExifDict.update(newCacheEntries)
            try:
                with open(exifCachePath() + ".tmp", 'wb') as cacheFile:
                    pickle.dump( (exifCacheVersion, cachedExifDict), cacheFile )
                os.replace(exifCachePath() + ".tmp", exifCachePath()) # atomic, a killed app can not leave a half written cache behind
            except: # e.g. read-only filesystem -> no cache this time, gets rebuilt on next start
                pass

    return fileInfoList


def scan4exifInfo(filePath, creationModificationDate, findExifAlbum, statResult, cachedExifInfo):
    estimatedSize = statResult.st_size

    # get timestamp from creation date
    if creationModificationDate == 0:
        timestampSource = "creationDate"
        timeMS_created = statResult.st_ctime #file first created in MS since 1970

    # OR get timestamp from modification date
    elif creationModificationDate == 1:
        timestampSource = "modificationDate"
        timeMS_created = statResult.st_mtime #file last modified in MS since 1970

    # OR get timestamp from parsing fileName
    else: #creationModificationDate == 2:
        timestampSource = "parsedFilename"
        try:
            try:
                match_str = (re.search(r'\d{4}\d{2}\d{2}', str(file))).group()
                match_str = match_str[:4] + "-" + match_str[4:]
                match_str = match_str[:7] + "-" + match_str[7:]
            except:
                match_str = (re.search(r'\d{4}-\d{2}-\d{2}', str(file))).group()
                #pyotherside.send('debugPythonLogs', "This filename is in a different format: " + file)

            #check if monthNr is actually not the dayNr, since some apps create YYYY/MM/DD and other YYYY/DD/MM
            if int(match_str[5:7]) > 12: # this will be a day then, since months only go up to 12
                timeUTC_fromFilename = datetime.datetime.strptime(match_str, '%Y-%d-%m').date()
            else:
                timeUTC_fromFilename = datetime.datetime.strptime(match_str, '%Y-%m-%d').date()

            # get a localized datetime object and convert to timestamp in MS
            dt = datetime.datetime(
                year=timeUTC_fromFilename.year,
                month=timeUTC_fromFilename.month,
                day=timeUTC_fromFilename.day
            ).replace(tzinfo=datetime.timezone.utc).astimezone(tz=None)
            timeMS_created = dt.timestamp()

        except: # creation date = fallback if filename makes no sense
            timestampSource = "creationDate"
            timeMS_created = statResult.st_ctime #file first created in MS since 1970
            #pyotherside.send('debugPythonLogs', "This filename can not be parsed for valid date: " + file)

    # try to find album and creation date time in metadata or filename - if enabled in settings ... ToDo: takes too long!!!
    foundAlbumTag = "|||"
    tempTimestampSource = timestampSource
    tempTimeMS_created = timeMS_created
    if findExifAlbum == 1: # if we scan for meta data in album
        # use cached values from a previous scan, no need to read the file again
        if cachedExifInfo is not None:
            if cachedExifInfo[0] != 0: # 0 means no exif datetime in this file
                timestampSource = "exifMetadata"
                timeMS_created = cachedExifInfo[0]
            foundAlbumTag = cachedExifInfo[1]

        else:
            # get EXIF date time
            if filePath.endswith( exifEnabledExtensions ):
                try:
                    exif_dict = piexif.load(filePath)
                    # check in first possible date block
                    if piexif.ImageIFD.DateTime in exif_dict["0th"]:
                        value = (exif_dict["0th"][piexif.ImageIFD.DateTime]).decode() # get rid of bytes format
                        timestampSource = "exifMetadata"
                        date_time_obj = datetime.datetime.strptime(str(value), '%Y:%m:%d %H:%M:%S')
                        timeMS_created = date_time_obj.timestamp()
                        #pyotherside.send('debugPythonLogs', "0th found some info: " + str(value) )
                    # check in second possible date block
                    elif piexif.ExifIFD.DateTimeOriginal in exif_dict["Exif"]:
                        value = (exif_dict["Exif"][piexif.ExifIFD.DateTimeOriginal]).decode() # get rid of bytes format
                        timestampSource = "exifMetadata"
                        date_time_obj = datetime.datetime.strptime(str(value), '%Y:%m:%d %H:%M:%S')
                        timeMS_created = date_time_obj.timestamp()
                        #pyotherside.send('debugPythonLogs', "EXIF found info: " + str(value) )
                    else:
                        timestampSource = tempTimestampSource
                        timeMS_created = tempTimeMS_created
                        #pyotherside.send('debugPythonLogs', "EXIF dict empty")
                except: # in case of error (e.g. non-ascii characters OR "0000:00:00 00:00:00" as value) -> use the date from previous info
                    timestampSource = tempTimestampSource
                    timeMS_created = tempTimeMS_created
                    #pyotherside.send('debugPythonLogs', "EXIF error parsing: " + filePath  )

            # get IPTC album keywords
            if filePath.endswith( iptcEnabledExtensions ):
                iptc_keywords = []
                foundAlbumTag = ""
                try:
                    iptc_info = iptcinfo3.IPTCInfo(filePath)
                    iptc_keywords = iptc_info['keywords']
                    if len(iptc_keywords) > 0:
                        for keyword in iptc_keywords:
                            if isinstance(keyword, bytes):
                                keyword = keyword.decode()
                            foundAlbumTag += str(keyword) + ", "
                        foundAlbumTag = foundAlbumTag[:-2]
                        #pyotherside.send('debugPythonLogs', foundAlbumTag )
                    else:
                        foundAlbumTag = "|||"
                except:
                    foundAlbumTag = "|||"

    # get creation date
    timeUTC_created = datetime.datetime.utcfromtimestamp(timeMS_created)
    # combine all infos and return to add to list
    return (timeMS_created, filePath, timeUTC_created.year, timeUTC_created.month, timeUTC_created.day, estimatedSize, foundAlbumTag, timestampSource)

    # run above as function with multithreading .. why is it slower than single thread???
    # with ThreadPoolExecutor() as executor:
    #     executor.map(scan4exifInfo, filteredFilePathList)






def findClosestDate ( datesItems, targetDate ):
    if targetDate in datesItems:
        closestDate = targetDate
    else:
        closestDate = min(datesItems, key=lambda x: abs(x - targetDate))
    closestIndex = datesItems.index(closestDate)
    pyotherside.send('goToDateIndex', closestIndex)


def getEXIFdata ( filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite ):
    iptc_keywords = []
    exifInfoList = []
    availableExifInfosList = []

    # get IPTC infos
    if filePath.endswith( iptcEnabledExtensions ):
        try:
            iptc_info = iptcinfo3.IPTCInfo(filePath)
            iptc_keywords = iptc_info['keywords']
            category = "IPTC Keywords"
            value = ""
            if len(iptc_keywords) > 0:
                for keyword in iptc_keywords:
                    if isinstance(keyword, bytes):
                        keyword = keyword.decode()
                    value += str(keyword) + ", "
                value = value[:-2]
                tag = 0
                ifd = "none"
                exifInfoList.append((category, value, tag, ifd))
            else:
                pyotherside.send('debugPythonLogs', "IPTC data available, but no keywords.")
        except:
            pyotherside.send('debugPythonLogs', "Reading IPTC data failed.")

    # get EXIF infos
    if filePath.endswith( exifEnabledExtensions ):
        try:
            exif_dict = piexif.load(filePath)
            for ifd in ("0th", "Exif", "GPS", "1st"):
                for tag in exif_dict[ifd]:
                    category = piexif.TAGS[ifd][tag]["name"]
                    value = exif_dict[ifd][tag]
                    if isinstance(category, bytes):
                        category = category.decode()
                    if isinstance(value, bytes):
                        value = value.decode()
                    exifInfoList.append((category, value, tag, ifd))
                    output = str(category) + " | " + str(value)
                    #pyotherside.send('debugPythonLogs', output)
        except:
            pyotherside.send('debugPythonLogs', "Reading EXIF data failed.")
    pyotherside.send('returnEXIFinfoList', exifInfoList, availableExifInfosList, filePath, creationDateMS, monthYear, day, folderPath, fileName, estimatedSize, album, imageWidth, imageHeight, timestampSource, isFavourite )
    exifInfoList = []



def changeCachedPaths ( cacheFilePath, cacheVersionWanted, removedPathList, renamedPathPairs ):
    # keep a cache consistent right away instead of waiting for the next scan to prune it,
    # renamed entries keep their value - a rename leaves the file contents and the mtime alone
    try:
        with open(cacheFilePath, 'rb') as cacheFile:
            cacheVersion, cachedDict = pickle.load(cacheFile)
        if cacheVersion != cacheVersionWanted:
            return
        changedAny = False
        for removedPath in removedPathList:
            if removedPath in cachedDict:
                del cachedDict[removedPath]
                changedAny = True
        for renamedPathPair in renamedPathPairs:
            if renamedPathPair[0] in cachedDict:
                cachedDict[renamedPathPair[1]] = cachedDict.pop(renamedPathPair[0])
                changedAny = True
        if changedAny:
            with open(cacheFilePath + ".tmp", 'wb') as cacheFile:
                pickle.dump( (cacheVersionWanted, cachedDict), cacheFile )
            os.replace(cacheFilePath + ".tmp", cacheFilePath)
    except: # missing or unreadable cache -> nothing to clean up here
        pass


def removeFromExifCache ( removedPathList ):
    changeCachedPaths( exifCachePath(), exifCacheVersion, removedPathList, [] )


def deleteFilesFunction ( deletePathArray ):
    deletedPathList = []
    failedPathList = []
    seenPathSet = set()
    for deletePath in deletePathArray:
        # guard against empty strings and duplicate paths, a failing os.remove used to abort the whole loop silently
        if deletePath == "" or deletePath in seenPathSet:
            continue
        seenPathSet.add( deletePath )
        try:
            os.remove ( deletePath )
            deletedPathList.append( deletePath )
        except:
            if os.path.exists( deletePath ): # still on disk -> deletion really failed
                failedPathList.append( deletePath )
            else: # was already gone -> report as deleted so QML cleans its lists anyway
                deletedPathList.append( deletePath )
    removeFromExifCache( deletedPathList )
    # QML removes the returned paths from all lists and the DB, or triggers a full rescan for big batches
    pyotherside.send('returnDeletedFiles', deletedPathList, failedPathList)


def checkFileExistence( inWhichTable, filePath ):
    if not os.path.exists(filePath):
        pyotherside.send('removeEntryFromDB', inWhichTable, filePath)
    pyotherside.send('finishedRemovingEntriesFromDB', )



def inspectImageFile ( filePath, deepCheck ):
    # the magic check is twelve bytes, cheap enough for every image the viewer opens,
    # the decode attempt only runs when something already went wrong (deepCheck)
    magicKinds = ( (b"\xff\xd8\xff", "jpg", (".jpg", ".jpeg")),
                   (b"\x89PNG\r\n\x1a\n", "png", (".png",)),
                   (b"GIF87a", "gif", (".gif",)),
                   (b"GIF89a", "gif", (".gif",)),
                   (b"BM", "bmp", (".bmp",)),
                   (b"II*\x00", "tif", (".tif", ".tiff")),
                   (b"MM\x00*", "tif", (".tif", ".tiff")) )
    try:
        fileSize = os.path.getsize(filePath)
        with open(filePath, 'rb') as imageFile:
            headBytes = imageFile.read(12)

        realKind = ""
        wantedExtensions = ()
        for magicBytes, kindName, kindExtensions in magicKinds:
            if headBytes.startswith(magicBytes):
                realKind = kindName
                wantedExtensions = kindExtensions
        if headBytes[:4] == b"RIFF" and headBytes[8:12] == b"WEBP": # webp carries its magic further in
            realKind = "webp"
            wantedExtensions = (".webp",)

        # the extension lies about the content, that is what makes the thumbnailer refuse the file
        if realKind != "" and not filePath.lower().endswith(wantedExtensions):
            dotIndex = filePath.rfind(".")
            baseName = filePath[:dotIndex] if dotIndex > filePath.rfind("/") else filePath
            suggestedFileName = (baseName + "." + realKind)[baseName.rfind("/")+1:]
            pyotherside.send('imageFileInspected', filePath, "wrongExtension", realKind, suggestedFileName, fileSize)
            return

        # extension and content agree, so ask pillow whether the data is usable at all
        if deepCheck is True:
            try:
                img = Image.open(filePath)
                img.load()
                img.close()
            except:
                pyotherside.send('imageFileInspected', filePath, "undecodable", realKind, "", fileSize)
                return

        pyotherside.send('imageFileInspected', filePath, "", realKind, "", fileSize)
    except: # not even readable
        pyotherside.send('imageFileInspected', filePath, "undecodable", "", "", 0)


def renameImageFile ( oldPath, targetStorageMedia, targetFolder, newFileName ):
    # renames in place when the current directory was chosen, otherwise moves the file along
    try:
        if "$CURRENT" in targetStorageMedia:
            targetDir = os.path.dirname(oldPath)
        elif "$HOME" in targetStorageMedia:
            targetDir = str(Path.home()) + targetFolder
        else:
            targetDir = str((glob.glob("/run/media/*/*"))[int(targetStorageMedia)-1]) + targetFolder
        newPath = targetDir + "/" + newFileName

        if newPath == oldPath: # nothing to do, but QML still gets its answer
            pyotherside.send('returnRenamedFile', oldPath, oldPath, "")
            return
        if os.path.exists(newPath): # never overwrite anything
            pyotherside.send('returnRenamedFile', oldPath, "", "exists")
            return

        shutil.move(oldPath, newPath) # os.rename alone cannot cross filesystems, eg. onto an sd card

        # the caches are keyed by path, move the entries over instead of losing them
        changeCachedPaths( exifCachePath(), exifCacheVersion, [], [ (oldPath, newPath) ] )
        changeCachedPaths( dHashCachePath(), dHashCacheVersion, [], [ (oldPath, newPath) ] )
        pyotherside.send('returnRenamedFile', oldPath, newPath, "")
    except: # nothing was changed that QML needs to know about
        pyotherside.send('returnRenamedFile', oldPath, "", "failed")


def checkCMDexistance ( command ) :
    returnCode = subprocess.call(['which', str(command)], stdout=subprocess.DEVNULL)
    if returnCode == 0:
        pyotherside.send('returnCommandExists', str(command) )
    else:
        pyotherside.send('returnCommandExists', 'file browser not installed')


def runCMDtool ( command ) :
    returnCode = subprocess.run([ command ])


def getAmountExtPartitions() :
    amountExternalPartitions = len(glob.glob("/run/media/*/*"))
    pyotherside.send('returnAmountExtPartitions', amountExternalPartitions)


def insertMetadataKeywords ( tags, filePath, storeWhere ):
    try:
        if "in_IPTC" in storeWhere and filePath.endswith( iptcEnabledExtensions ):
            iptc_info = iptcinfo3.IPTCInfo(filePath, force=True)
            iptc_info['keywords'].clear()
            allKeywordsList = []
            allKeywordsList = tags.split(",")
            for keyWord in allKeywordsList:
                keyWord = keyWord.strip() #removes whitespaces from beginning and end
                if len(keyWord) > 0:
                    iptc_info['keywords'].append(bytes(keyWord, 'UTF-8'))
            iptc_info.save()  #iptc_info.save_as(filePath)
            #pyotherside.send('debugPythonLogs', "album in iptc saved")
        elif "in_EXIF" in storeWhere and filePath.endswith( iptcEnabledExtensions ):
            zeroth_ifd = {40094: tags.encode('utf16')} #=> piexif.ImageIFD.XPKeywords: "keywords_here".encode('utf16')
            exif_bytes = piexif.dump({"0th":zeroth_ifd})
            piexif.insert(exif_bytes, filePath)
            #pyotherside.send('debugPythonLogs', "album in exif saved")
    except:
        pyotherside.send('debugPythonLogs', "Adding Metadata not supported with this file.")

def editEXIFdata ( filePath, ifdZone, tagNr, tagName, tagValue ):
    if filePath.endswith( exifEnabledExtensions ):
        # insert EXIF infos
        #pyotherside.send('debugPythonLogs', ifdZone)
        #pyotherside.send('debugPythonLogs', tagNr)
        #pyotherside.send('debugPythonLogs', tagName)
        #pyotherside.send('debugPythonLogs', tagValue)
        try:
            exif_dict = piexif.load(filePath)
            exif_dict[ifdZone][tagNr] = tagValue.encode()
            '''
            for ifd in ("0th", "Exif", "GPS", "1st"):
                for tag in exif_dict[ifd]:
                    exif_dict[ifdZone][tagNr] = tagValue.encode()
                    #category = piexif.TAGS[ifd][tag]["name"]
                    # if isinstance(category, bytes):
                    #     category = category.decode()
                    # if str(category) in str(tagName):
                    #     exif_dict[ifd][tag] = tagValue.encode()
            '''
            exif_bytes = piexif.dump(exif_dict)
            piexif.insert(exif_bytes, filePath)
        except:
            pyotherside.send('debugPythonLogs', "Writing EXIF data failed, but life goes on.")
    pyotherside.send('finishedWritingMetadata', )



def removeMetadataKeywords ( filePath, storeWhere ):
    try:
        if "in_IPTC" in storeWhere and filePath.endswith( iptcEnabledExtensions ):
            iptc_info = iptcinfo3.IPTCInfo(filePath)
            iptc_info['keywords'].clear()
            iptc_info.save()
    except:
        pyotherside.send('debugPythonLogs', "Deleting Metadata not supported with this file.")


def packZipImagesTmp ( imagePathsList ) :
    targetPath = str(Path.home()) + "/Downloads/" + "ImgOrganizer.zip"
    allfilePathList = []
    allfilePathList = imagePathsList.split("|||")
    with zipfile.ZipFile(targetPath , "w") as zipF:
        for file in allfilePathList:
            if len(file) > 0:
                name_file_only= file.split(os.sep)[-1]
                zipF.write(file, name_file_only, compress_type=zipfile.ZIP_DEFLATED)
    pyotherside.send('zipFileCreated', targetPath)


# general color conversion functions
def argb2rgba ( paintColor ) :
    first2 = paintColor[1:3]
    last6 = paintColor[3:9]
    rgbaColor = "#" + last6 + first2
    return rgbaColor

def argb2rgb ( paintColor ) :
    first2 = paintColor[1:3]
    last6 = paintColor[3:9]
    rgbColor = "#" + last6
    return rgbColor

def rgb2argb ( paintColor ) :
    first2 = "ff"
    last6 = paintColor[1:7]
    argbColor = "#" + first2 + last6
    return argbColor

def argb2alpha ( paintColor ) :
    first2 = paintColor[1:3]
    alphaValue = int(first2, 16)
    return alphaValue



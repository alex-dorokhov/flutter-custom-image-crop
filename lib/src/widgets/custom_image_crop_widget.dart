import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:custom_image_crop/src/clippers/inverted_clipper.dart';
import 'package:custom_image_crop/src/controllers/controller.dart';
import 'package:custom_image_crop/src/models/model.dart';
import 'package:custom_image_crop/src/painters/dotted_path_painter.dart';
import 'package:flutter/material.dart';
import 'package:gesture_x_detector/gesture_x_detector.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;

/// An image cropper that is customizable.
/// You can rotate, scale and translate either
/// through gestures or a controller
class CustomImageCrop extends StatefulWidget {
  /// The image to crop
  final ImageProvider image;

  /// The controller that handles the cropping and
  /// changing of the cropping area
  final CustomImageCropController cropController;

  /// The color behind the cropping area
  final Color backgroundColor;

  /// The color in front of the cropped area
  final Color overlayColor;

  /// The shape of the cropping area
  final CustomCropShape shape;

  /// The percentage of the available area that is
  /// reserved for the cropping area
  final double cropPercentage;

  /// width / height
  final double aspectRatio;

  /// The path drawer of the border see [DottedCropPathPainter],
  /// [SolidPathPainter] for more details or how to implement a
  /// custom one
  final CustomPaint Function(Path) drawPath;

  /// The paint used when drawing an image before cropping
  final Paint imagePaintDuringCrop;

  /// A custom image cropper widget
  ///
  /// Uses a `CustomImageCropController` to crop the image.
  /// With the controller you can rotate, translate and/or
  /// scale with buttons and sliders. This can also be
  /// achieved with gestures
  ///
  /// Use a `shape` with `CustomCropShape.Circle` or
  /// `CustomCropShape.Square`
  ///
  /// You can increase the cropping area using `cropPercentage`
  ///
  /// Change the cropping border by changing `drawPath`,
  /// we've provided two default painters as inspiration
  /// `DottedCropPathPainter.drawPath` and
  /// `SolidCropPathPainter.drawPath`
  CustomImageCrop({
    required this.image,
    required this.cropController,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 0.5),
    this.backgroundColor = Colors.white,
    this.shape = CustomCropShape.Circle,
    this.cropPercentage = 0.8,
    this.aspectRatio = 1.0,
    this.drawPath = DottedCropPathPainter.drawPath,
    Paint? imagePaintDuringCrop,
    Key? key,
  })  : this.imagePaintDuringCrop = imagePaintDuringCrop ?? (Paint()..filterQuality = FilterQuality.high),
        super(key: key);

  @override
  _CustomImageCropState createState() => _CustomImageCropState();
}

class _CustomImageCropState extends State<CustomImageCrop> with CustomImageCropListener {
  late Path _path;
  late double _width, _height;
  ui.Image? _imageAsUIImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double _uiImageScale = 1;
  Matrix4 _transformMatrix = Matrix4.identity();
  Matrix4 _scaleStartTransformMatrix = Matrix4.zero();
  Matrix4 _tempScaleMatrix = Matrix4.identity();
  Matrix4 _uiTransformMatrix = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    widget.cropController.addListener(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getImage();
  }

  void _getImage() {
    final oldImageStream = _imageStream;
    _imageStream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key != oldImageStream?.key) {
      if (_imageListener != null) {
        oldImageStream?.removeListener(_imageListener!);
      }
      _imageListener = ImageStreamListener(_updateImage);
      _imageStream?.addListener(_imageListener!);
    }
  }

  void _updateImage(ImageInfo imageInfo, _) {
    setState(() {
      _imageAsUIImage = imageInfo.image;
    });
  }

  @override
  void dispose() {
    if (_imageListener != null) {
      _imageStream?.removeListener(_imageListener!);
    }
    widget.cropController.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageAsUIImage;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        final cropWidth = min(_width, _height) * widget.cropPercentage;
        final cropHeight = cropWidth / widget.aspectRatio;
        final defaultScale = cropWidth / max(image.width, image.height);
        _uiImageScale = data.scale * defaultScale;
        _uiTransformMatrix
          ..setIdentity()
          ..scale(_uiImageScale)
          ..multiply(_transformMatrix);
        _path = _getPath(cropWidth, cropHeight, _width, _height);
        return XGestureDetector(
          onMoveUpdate: onMoveUpdate,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          child: Container(
            width: _width,
            height: _height,
            color: widget.backgroundColor,
            child: Stack(
              children: [
                Positioned(
                  left: data.x + (_width - cropWidth) / 2,
                  top: data.y + (_height - cropHeight) / 2,
                  child: Transform(
                    transform: _uiTransformMatrix,
                    child: Image(
                      image: widget.image,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: ClipPath(
                    clipper: InvertedClipper(_path, _width, _height),
                    child: Container(
                      color: widget.overlayColor,
                    ),
                  ),
                ),
                widget.drawPath(_path),
              ],
            ),
          ),
        );
      },
    );
  }

  void onScaleStart(_) {
    _scaleStartTransformMatrix.setFrom(_transformMatrix);
  }

  void onScaleUpdate(ScaleEvent event) {
    final startMatrix = _scaleStartTransformMatrix;
    final tempMatrix = _tempScaleMatrix;
    final cropWidth = min(_width, _height) * widget.cropPercentage;
    final cropHeight = cropWidth /widget.aspectRatio;
    final clipCenterX = cropWidth / 2 / _uiImageScale;
    final clipCenterY = cropHeight / 2 / _uiImageScale;
    final imageOrigin = vector_math.Vector3(clipCenterX, clipCenterY, 0)
      ..applyMatrix4(tempMatrix
        ..setFrom(startMatrix)
        ..invert());
    tempMatrix
      ..setFromTranslationRotationScale(
          imageOrigin,
          vector_math.Quaternion.axisAngle(vector_math.Vector3(0, 0, 1), -event.rotationAngle),
          vector_math.Vector3(event.scale, event.scale, 1.0))
      ..translate(-imageOrigin);
    setState(() {
      _transformMatrix
        ..setFrom(startMatrix)
        ..multiply(_tempScaleMatrix);
    });
  }

  void onMoveUpdate(MoveEvent event) {
    setState(() {
      _transformMatrix.leftTranslate(event.delta.dx / _uiImageScale, event.delta.dy / _uiImageScale);
    });
  }

  Path _getPath(double cropWidth, double cropHeight, double width, double height) {
    switch (widget.shape) {
      case CustomCropShape.Circle:
        return Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(width / 2, height / 2),
              radius: cropWidth / 2,
            ),
          );
      default:
        return Path()
          ..addRect(
            Rect.fromCenter(
              center: Offset(width / 2, height / 2),
              width: cropWidth,
              height: cropHeight,
            ),
          );
    }
  }

  @override
  Future<MemoryImage?> onCropImage() async {
    if (_imageAsUIImage == null) {
      return null;
    }
    final imageWidth = _imageAsUIImage!.width;
    final imageHeight = _imageAsUIImage!.height;
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final cropWidth = max(imageWidth, imageHeight).toDouble();
    final cropHeight = cropWidth / widget.aspectRatio;
    final clipPath = Path.from(_getPath(cropWidth, cropHeight, cropWidth, cropHeight));
    final bgPaint = Paint()
      ..color = widget.backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, cropWidth, cropHeight), bgPaint);
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.transform(_transformMatrix.storage);
    canvas.drawImage(_imageAsUIImage!, Offset.zero, widget.imagePaintDuringCrop);
    canvas.restore();

    // Optionally remove magenta from image by evaluating every pixel
    // See https://github.com/brendan-duncan/image/blob/master/lib/src/transform/copy_crop.dart

    // final bytes = await compute(computeToByteData, <String, dynamic>{'pictureRecorder': pictureRecorder, 'cropWidth': cropWidth});

    ui.Picture picture = pictureRecorder.endRecording();
    ui.Image image = await picture.toImage(cropWidth.floor(), cropHeight.floor());

    // Adding compute would be preferrable. Unfortunately we cannot pass an ui image to this.
    // A workaround would be to save the image and load it inside of the isolate
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes == null ? null : MemoryImage(bytes.buffer.asUint8List());
  }

  @override
  void addTransition(CropImageData transition) {
    setState(() {
      data += transition;
      // For now, this will do. The idea is that we create
      // a path from the data and check if when we combine
      // that with the crop path that the resulting path
      // overlap the hole (crop). So we check if all pixels
      // from the crop contain pixels from the original image
      data.scale = data.scale.clamp(0.1, 10.0);
    });
  }

  @override
  void setData(CropImageData newData) {
    setState(() {
      data = newData;
      // The same check should happen (once available) as in addTransition
      data.scale = data.scale.clamp(0.1, 10.0);
    });
  }
}

enum CustomCropShape {
  Circle,
  Square,
}

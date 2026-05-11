/// Draw command model for canvas rendering
class DrawCommand {
  final String type;
  final int timestamp; // milliseconds
  final String action;
  final List<double>? bbox; // [x1, y1, x2, y2]
  final String? content;
  final DrawStyle? style;
  final AnimationConfig? animation;

  DrawCommand({
    this.type = 'draw',
    required this.timestamp,
    required this.action,
    this.bbox,
    this.content,
    this.style,
    this.animation,
  });

  factory DrawCommand.fromJson(Map<String, dynamic> json) {
    return DrawCommand(
      type: json['type'] ?? 'draw',
      timestamp: json['ts'] ?? json['timestamp'] ?? 0,
      action: json['action'] ?? '',
      bbox: json['bbox'] != null
          ? List<double>.from(json['bbox'].map((e) => (e as num).toDouble()))
          : null,
      content: json['content'],
      style: json['style'] != null ? DrawStyle.fromJson(json['style']) : null,
      animation: json['animation'] != null
          ? AnimationConfig.fromJson(json['animation'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'ts': timestamp,
      'action': action,
      if (bbox != null) 'bbox': bbox,
      if (content != null) 'content': content,
      if (style != null) 'style': style!.toJson(),
      if (animation != null) 'animation': animation!.toJson(),
    };
  }
}

class DrawStyle {
  final String? color;
  final String? fontSize; // 'small', 'medium', 'large', 'xlarge'
  final bool? handwriting;
  final int? strokeWidth;
  final bool? dashed;
  final double? opacity;

  DrawStyle({
    this.color,
    this.fontSize,
    this.handwriting,
    this.strokeWidth,
    this.dashed,
    this.opacity,
  });

  factory DrawStyle.fromJson(Map<String, dynamic> json) {
    return DrawStyle(
      color: json['color'],
      fontSize: json['fontSize'],
      handwriting: json['handwriting'],
      strokeWidth: json['strokeWidth'],
      dashed: json['dashed'],
      opacity: json['opacity']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (color != null) 'color': color,
      if (fontSize != null) 'fontSize': fontSize,
      if (handwriting != null) 'handwriting': handwriting,
      if (strokeWidth != null) 'strokeWidth': strokeWidth,
      if (dashed != null) 'dashed': dashed,
      if (opacity != null) 'opacity': opacity,
    };
  }
}

class AnimationConfig {
  final int duration; // milliseconds
  final String? easing; // 'linear', 'easeInOut', etc.

  AnimationConfig({
    this.duration = 300,
    this.easing,
  });

  factory AnimationConfig.fromJson(Map<String, dynamic> json) {
    return AnimationConfig(
      duration: json['duration'] ?? 300,
      easing: json['easing'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      if (easing != null) 'easing': easing,
    };
  }
}

/// Supported draw actions
class DrawAction {
  static const String write = 'write';
  static const String circle = 'circle';
  static const String underline = 'underline';
  static const String arrow = 'arrow';
  static const String highlight = 'highlight';
  static const String tick = 'tick';
  static const String cross = 'cross';
  static const String erase = 'erase';
  static const String clear = 'clear';
}

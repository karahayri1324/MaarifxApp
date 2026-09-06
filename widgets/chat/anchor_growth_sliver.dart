import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Ters (reverse) sohbet listesinin DİBİNDEKİ "çapa" balonunu saran sliver.
/// Çapa = en yeni mesaj; akış (streaming) sırasında boyu her token'da büyür.
///
/// ## Sorun
/// Ters listede çapa scroll offset 0'da durur, ondan ÖNCEKİ tüm mesajlar onun
/// arkasından gelir. Çapa büyüyünce üstteki her şeyin scroll offset'i de aynı
/// miktarda büyür. Kullanıcı yukarı kaydırmışsa (pixels > 0) okuduğu satır her
/// token'da yer değiştirir.
///
/// ## Eski çözüm ve neden atıldı
/// Boy farkı `addPostFrameCallback` içinde GlobalKey ile ölçülüp `jumpTo` ile
/// telafi ediliyordu. İki kusuru vardı:
///  1. Telafi kare ÇİZİLDİKTEN sonra uygulanıyordu: her büyümede bir karelik
///     yanlış konum ekrana çıkıp bir sonraki karede geri alınıyordu — kullanıcı
///     bunu "pırpır" olarak görüyordu.
///  2. `ScrollPositionWithSingleContext.jumpTo` önce `goIdle()` çağırır: parmak
///     ekrandayken sürükleme etkinliğini ve atalet (ballistic) kaydırmasını
///     iptal eder, sonra `goBallistic(0)` ile yenisini başlatır. Akış boyunca
///     saniyede onlarca kez tekrarlandığı için yukarı kaydırma sürekli
///     kesiliyordu.
///
/// ## Bu çözüm
/// Telafi LAYOUT içinde, sliver protokolünün kendi mekanizmasıyla yapılır:
/// boy değiştiğinde [SliverGeometry.scrollOffsetCorrection] döndürülür,
/// `RenderViewport.performLayout` offset'i `correctBy` ile düzeltip layout'u
/// AYNI karede tekrarlar. Sonuç:
///  * ekrana hiçbir zaman yanlış konumlu kare çıkmaz (pırpır yok),
///  * `correctBy` etkinliği değiştirmediği için aktif sürükleme/atalet bozulmaz,
///  * çapa görüş alanı dışına çıksa bile ölçülür (kendi sliver'ı asla çöpe
///    toplanmaz), böylece telafi her kaydırma konumunda tutarlı çalışır.
class AnchorGrowthSliver extends SingleChildRenderObjectWidget {
  const AnchorGrowthSliver({
    super.key,
    required this.anchorId,
    required Widget super.child,
  });

  /// Çapadaki mesajın kimliği. Değişmesi "artık başka bir balon ölçülüyor"
  /// demektir; iki farklı balonun boy farkı anlamsız olduğu için o karede
  /// telafi uygulanmaz, yalnız yeni taban alınır.
  final String anchorId;

  @override
  RenderAnchorGrowthSliver createRenderObject(BuildContext context) =>
      RenderAnchorGrowthSliver(anchorId: anchorId);

  @override
  void updateRenderObject(
      BuildContext context, RenderAnchorGrowthSliver renderObject) {
    renderObject.anchorId = anchorId;
  }
}

/// [AnchorGrowthSliver]'ın render nesnesi. Gövdesi [RenderSliverToBoxAdapter]
/// ile birebir aynıdır; tek fark boy değişimini yakalayıp
/// [SliverGeometry.scrollOffsetCorrection] döndürmesidir.
class RenderAnchorGrowthSliver extends RenderSliverSingleBoxAdapter {
  RenderAnchorGrowthSliver({required String anchorId}) : _anchorId = anchorId;

  /// Alt piksel gürültüsünü telafi etmemek için eşik. Bunun altındaki farklar
  /// tabana İŞLENMEZ; işlenseydi kare kare birikip görünür kaymaya dönüşürdü.
  static const double _esik = 0.01;

  String _anchorId;
  String get anchorId => _anchorId;
  set anchorId(String value) {
    if (_anchorId == value) return;
    _anchorId = value;
    _tabanBoy = null;
  }

  /// En son telafi edilmiş (ya da dipteyken kaydedilmiş) çapa boyu.
  double? _tabanBoy;

  @override
  void performLayout() {
    if (child == null) {
      _tabanBoy = null;
      geometry = SliverGeometry.zero;
      return;
    }
    final SliverConstraints constraints = this.constraints;
    child!.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final double childExtent = switch (constraints.axis) {
      Axis.horizontal => child!.size.width,
      Axis.vertical => child!.size.height,
    };

    final double? taban = _tabanBoy;
    if (taban == null || constraints.scrollOffset <= _esik) {
      // Taban yok ya da kullanıcı dipte: büyüme zaten doğru yönde görünür,
      // telafi gerekmez; yalnız taban güncellenir.
      _tabanBoy = childExtent;
    } else {
      final double fark = childExtent - taban;
      if (fark.abs() > _esik) {
        _tabanBoy = childExtent;
        // Küçülmede offset'i 0'ın altına itme: viewport'u geçersiz konuma
        // sokup gereksiz atalet düzeltmesi tetiklerdi.
        final double duzeltme = math.max(fark, -constraints.scrollOffset);
        if (duzeltme.abs() > precisionErrorTolerance) {
          geometry = SliverGeometry(scrollOffsetCorrection: duzeltme);
          return; // viewport offset'i düzeltip bu layout'u tekrarlayacak
        }
      }
    }

    final double paintedChildSize =
        calculatePaintOffset(constraints, from: 0.0, to: childExtent);
    final double cacheExtent =
        calculateCacheOffset(constraints, from: 0.0, to: childExtent);

    assert(paintedChildSize.isFinite);
    assert(paintedChildSize >= 0.0);
    geometry = SliverGeometry(
      scrollExtent: childExtent,
      paintExtent: paintedChildSize,
      cacheExtent: cacheExtent,
      maxPaintExtent: childExtent,
      hitTestExtent: paintedChildSize,
      hasVisualOverflow: childExtent > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0.0,
    );
    setChildParentData(child!, constraints, geometry!);
  }
}

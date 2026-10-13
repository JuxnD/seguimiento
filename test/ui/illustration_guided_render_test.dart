import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import '../support/test_fonts.dart';

void main() {
  final output=Platform.environment['GUIDED_RENDER_OUT'];
  final clipName=Platform.environment['GUIDED_RENDER_CLIP'];
  final source=Platform.environment['ILLUSTRATION_035_SOURCE_SHA'];
  final raw=jsonDecode(File(Figure3DCatalog.asset).readAsStringSync()) as Map<String,Object?>;
  final catalog=Figure3DCatalog.fromJsonString(jsonEncode(raw));

  void paint(Canvas canvas,Figure3D fig,double progress,double yaw,String label) {
    canvas.save();
    Figure3DPainter(fig,progress,yaw:yaw,pitch:fig.initialPitch).paint(canvas,const Size(360,315));
    canvas.restore();
    final text=TextPainter(text:TextSpan(text:'${fig.name} · $label\n'
        '${fig.frames[(fig.frameCoordinate(progress)).round()].caption}',
        style:const TextStyle(color:Colors.white,fontFamily:'Roboto',fontSize:12)),textDirection:TextDirection.ltr,maxLines:4)
      ..layout(maxWidth:350);
    text.paint(canvas,const Offset(5,320));text.dispose();
  }
  Future<void> save(ui.Picture picture,String path,int width,int height,WidgetTester tester) async {
    await tester.runAsync(() async {
      final image=await picture.toImage(width,height);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
    });
    picture.dispose();
  }

  testWidgets('guided production keyframes from two cameras', (tester) async {
    await loadTestFonts(tester);
    expect(source,matches(RegExp(r'^[a-f0-9]{40}$')));
    Directory(output!).createSync(recursive:true);
    final entries=<({String name,String? key,Figure3D figure})>[
      for(final f in (raw['figures'] as List).cast<Map<String,Object?>>())
        if((f['source'] as String).startsWith('Plan v3.2'))
          (name:f['name'] as String,key:null,figure:catalog.forExercise(f['name'] as String)!),
      for(final v in (raw['physicalVariants'] as List).cast<Map<String,Object?>>())
        if(v['useBase']!=true)
          (name:v['exercise'] as String,key:v['key'] as String,
           figure:catalog.forExercise(v['exercise'] as String,physicalVariantKey:v['key'] as String)!),
    ];
    expect(entries.length,38);
    final manifest=<Map<String,Object?>>[];
    for(final (number,entry) in entries.indexed) {
      final fig=entry.figure;
      final hold=fig.motion.indexWhere((s)=>s.kind=='hold');
      final indices=fig.frames.length<=12 ? [for(var i=0;i<fig.frames.length;i++) i] :
        ({0,fig.frames.length-1,hold,hold+1,hold~/2,hold+(fig.frames.length-hold)~/2}.toList()..sort());
      final angles=[fig.initialYaw,fig.initialYaw<45?70.0:0.0];
      final count=indices.length*angles.length;
      const columns=4;
      final recorder=ui.PictureRecorder();
      final canvas=Canvas(recorder)..drawColor(const Color(0xff0b0806),BlendMode.src);
      final samples=<Map<String,Object?>>[];
      var cell=0;
      for(final yaw in angles) {
        for(final index in indices) {
          final progress=index/(fig.frames.length-1);
          final body=liftSkeleton(fig.skeletonAt(progress),fig);
          canvas.save();canvas.translate((cell%columns)*360.0,(cell~/columns)*400.0);
          paint(canvas,fig,progress,yaw,'${entry.key??'base'} · key$index · yaw$yaw');
          canvas.restore();cell++;
          samples.add({'keyframe':index,'progress':progress,'yaw':yaw,'pitch':fig.initialPitch,
            'joints':{for(final e in body.p.entries) e.key:[e.value.x,e.value.y,e.value.z]}});
        }
      }
      final path='$output/${(number+1).toString().padLeft(2,'0')}.png';
      await save(recorder.endRecording(),path,360*columns,400*(count/columns).ceil(),tester);
      manifest.add({'name':entry.name,'physicalVariantKey':entry.key,'sourceCommit':source,
        'path':path,'allKeyframes':fig.frames.length,'selectedKeyframes':indices,'samples':samples});
    }
    File('$output/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  },skip:output==null||clipName!=null);

  testWidgets('guided anatomical detail follows production time at twenty fps', (tester) async {
    await loadTestFonts(tester);
    expect(source,matches(RegExp(r'^[a-f0-9]{40}$')));
    expect(clipName,isIn(['Gato-camello','Pie corto']));
    final fig=catalog.forExercise(clipName!)!;
    final duration=fig.motion.fold<double>(0,(sum,s)=>sum+s.seconds);
    const fps=20;
    final count=(duration*fps).round();
    Directory(output!).createSync(recursive:true);
    final samples=<Map<String,Object?>>[];
    for(var frame=0;frame<count;frame++) {
      final seconds=frame/fps;
      final progress=figureMotionProgress(fig,seconds);
      final recorder=ui.PictureRecorder();
      final canvas=Canvas(recorder)..drawColor(const Color(0xff0b0806),BlendMode.src);
      paint(canvas,fig,progress,fig.initialYaw,figureMotionCaption(fig,progress));
      final path='$output/${frame.toString().padLeft(4,'0')}.png';
      await save(recorder.endRecording(),path,360,400,tester);
      samples.add({'frame':frame,'timestampSeconds':seconds,'progress':progress,'yaw':fig.initialYaw,'pitch':fig.initialPitch});
    }
    File('$output/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'name':clipName,'sourceCommit':source,'fps':fps,'duration':duration,'frames':count,
      'timeline':'figureMotionProgress production, no rescaling','samples':samples}));
  },skip:output==null||clipName==null);
}

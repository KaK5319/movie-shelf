import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

/// 映画棚 - 自分のスマホ内の映画・ドラマファイルを並べる棚アプリ。
/// 大きな動画ファイルはアプリ内にコピーせず、選んだファイルのパスと情報だけを保存する。

// ---------- 見た目の色(明るい木の棚) ----------
const Color kCream = Color(0xFFF7EFE3); // 背景の温かいクリーム色
const Color kCard = Color(0xFFFFFDF8); // カードの温かい白
const Color kWood = Color(0xFF7A4A21); // アクセントの木の茶色
const Color kWoodBar = Color(0xFF8D5A33); // AppBarの木の茶色
const Color kInk = Color(0xFF2B211B); // 本文の濃い茶色
const Color kSub = Color(0xFF7A6A5F); // 補足テキストの茶灰色
const Color kContinue = Color(0xFFC62828); // つづきマークの赤
const Color kContinueBg = Color(0xFFFDECEA); // つづきマークの薄い赤背景
const Color kEpisode = Color(0xFF9C6B00); // 話数表示の濃い琥珀色
const Color kStar = Color(0xFFF2A007); // 星の色
const Color kWatched = Color(0xFF2E7D32); // 「観た」の緑

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const EigadanaApp());
}

class EigadanaApp extends StatelessWidget {
  const EigadanaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '映画棚',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: kCream,
          colorScheme: ColorScheme.fromSeed(seedColor: kWood, brightness: Brightness.light).copyWith(
            primary: kWood,
            onPrimary: Colors.white,
            secondary: kWoodBar,
            surface: kCream,
            onSurface: kInk,
          ),
          appBarTheme: const AppBarTheme(backgroundColor: kWoodBar, foregroundColor: Colors.white),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: kInk,
            contentTextStyle: TextStyle(color: Colors.white),
          ),
        ),
        home: const HomePage(),
      );
}

// ---------- データ ----------

class Shelf {
  Shelf(this.id, this.name);
  final String id;
  String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Shelf.fromJson(Map<String, dynamic> j) => Shelf(j['id'] as String, j['name'] as String);
}

class Work {
  Work({
    required this.id,
    required this.title,
    this.shelfId = '',
    this.episode,
    this.fileName = '',
    this.filePath = '',
    this.fileSizeBytes = 0,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.watched = false,
    this.rating = 0,
    this.memo = '',
    this.sortOrder = 0,
  });
  final String id;
  String title;
  String shelfId; // '' = 棚なし
  int? episode;
  String fileName;
  String filePath;
  int fileSizeBytes;
  int positionSeconds;
  int durationSeconds;
  bool watched;
  int rating; // 0-5
  String memo;
  int sortOrder;

  /// 最後まで観たとみなす位置か(残り5%以下、または残り90秒以下)
  bool get isAtEnd {
    if (durationSeconds <= 0) return false;
    final pos = positionSeconds;
    final dur = durationSeconds;
    return pos >= dur * 0.95 || dur - pos <= 90;
  }

  /// 10秒以上観ていて、まだ最後まで行っていない = つづきあり
  bool get isInProgress => !watched && positionSeconds >= 10 && durationSeconds > 0 && !isAtEnd;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'shelfId': shelfId,
        'episode': episode,
        'fileName': fileName,
        'filePath': filePath,
        'fileSizeBytes': fileSizeBytes,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'watched': watched,
        'rating': rating,
        'memo': memo,
        'sortOrder': sortOrder,
      };
  factory Work.fromJson(Map<String, dynamic> j) => Work(
        id: j['id'] as String,
        title: j['title'] as String,
        shelfId: (j['shelfId'] ?? '') as String,
        episode: j['episode'] as int?,
        fileName: (j['fileName'] ?? '') as String,
        filePath: (j['filePath'] ?? '') as String,
        fileSizeBytes: (j['fileSizeBytes'] ?? 0) as int,
        positionSeconds: (j['positionSeconds'] ?? 0) as int,
        durationSeconds: (j['durationSeconds'] ?? 0) as int,
        watched: (j['watched'] ?? false) as bool,
        rating: (j['rating'] ?? 0) as int,
        memo: (j['memo'] ?? '') as String,
        sortOrder: (j['sortOrder'] ?? 0) as int,
      );
}

// ---------- 作品タイルの色 ----------
// Web版の棚と同じく、作品ごとに濃い「ポスター色」を付けるためのパレット。
// 保存データは変えず、タイトルと話数から毎回同じ色を導くので、
// 同じ作品はいつ開いても同じ色になる。
const List<Color> kTilePalette = [
  Color(0xFF2E5E43), // 深い緑
  Color(0xFF5B2A6E), // 紫
  Color(0xFF6B4226), // 茶
  Color(0xFF20545A), // 青緑(ティール)
  Color(0xFF8A3B12), // 錆色(ラスト)
  Color(0xFF26306E), // 紺
  Color(0xFF5E2144), // ワイン
  Color(0xFF1F4634), // 濃い緑
];

// グラデーションの下側(同じ色相の少し暗い色)
const List<Color> kTilePaletteDark = [
  Color(0xFF1E4030),
  Color(0xFF3E1C4B),
  Color(0xFF472C17),
  Color(0xFF143A3F),
  Color(0xFF5F280B),
  Color(0xFF181F49),
  Color(0xFF3F152E),
  Color(0xFF132E22),
];

/// タイトルの安定ハッシュ(FNV-1a)。
/// String.hashCodeは実行ごとに変わり得るので使わない。
int _titleHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// 作品のタイル色の番号: (話数 + タイトルのハッシュ) % パレット数。
/// 話数を足すため、同じドラマでも隣り合う話は必ず別の色になる。
int tileIndexFor(Work w) => ((w.episode ?? 0) + _titleHash(w.title)) % kTilePalette.length;

/// アプリ全体のデータ。どの画面からも同じものを見る
class AppData {
  AppData._();
  static final AppData I = AppData._();
  final List<Shelf> shelves = [];
  final List<Work> works = [];
  bool loaded = false;

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/eigadana_data.json');
  }

  Map<String, dynamic> encode() => {
        'shelves': shelves.map((s) => s.toJson()).toList(),
        'works': works.map((w) => w.toJson()).toList(),
      };

  void decode(Map<String, dynamic> j) {
    shelves
      ..clear()
      ..addAll(((j['shelves'] ?? []) as List).map((e) => Shelf.fromJson(e as Map<String, dynamic>)));
    works
      ..clear()
      ..addAll(((j['works'] ?? []) as List).map((e) => Work.fromJson(e as Map<String, dynamic>)));
    loaded = true;
  }

  Future<void> load() async {
    if (loaded) return;
    final f = await _dataFile();
    if (await f.exists()) {
      decode(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } else {
      loaded = true;
    }
  }

  Future<void> save() async {
    final f = await _dataFile();
    await f.writeAsString(jsonEncode(encode()));
  }

  List<Work> worksOf(String shelfId) {
    final list = works.where((w) => w.shelfId == shelfId).toList();
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      final ea = a.episode ?? 99999;
      final eb = b.episode ?? 99999;
      if (ea != eb) return ea.compareTo(eb);
      return a.title.compareTo(b.title);
    });
    return list;
  }

  int nextSortOrder(String shelfId) {
    var m = -1;
    for (final w in worksOf(shelfId)) {
      if (w.sortOrder > m) m = w.sortOrder;
    }
    return m + 1;
  }

  /// その棚の「つづき」の作品: 観かけのもの優先。なければ最後に観終わった話の次の未視聴話
  Work? continueWork(String shelfId) {
    final list = worksOf(shelfId);
    for (final w in list) {
      if (w.isInProgress) return w;
    }
    var lastWatched = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i].watched) lastWatched = i;
    }
    if (lastWatched >= 0) {
      for (var i = lastWatched + 1; i < list.length; i++) {
        if (!list[i].watched) return list[i];
      }
    }
    return null;
  }
}

String newId() => '${DateTime.now().microsecondsSinceEpoch}';

/// ファイル名の自然順(2 < 10)
int natCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m.group(0)!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final na = int.tryParse(ra[i]);
    final nb = int.tryParse(rb[i]);
    if (na != null && nb != null) {
      if (na != nb) return na.compareTo(nb);
    } else {
      final c = ra[i].compareTo(rb[i]);
      if (c != 0) return c;
    }
  }
  return ra.length.compareTo(rb.length);
}

String fmtSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
  return '${(bytes / 1024).toStringAsFixed(0)}KB';
}

String fmtTime(int sec) {
  if (sec < 0) sec = 0;
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

const videoExtensions = ['mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', '3gp', 'wmv', 'flv', 'ts'];

// ---------- ホーム(棚の箱一覧) ----------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppData.I.load();
    } catch (e) {
      _error = '読み込みに失敗しました。棚や作品が消えたわけではありません。\n$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newShelf() async {
    final name = await _textDialog('新しい棚の箱を作る', '棚の名前', '');
    if (name == null || name.trim().isEmpty) return;
    AppData.I.shelves.add(Shelf(newId(), name.trim()));
    await AppData.I.save();
    setState(() {});
  }

  Future<void> _renameShelf(Shelf s) async {
    final name = await _textDialog('棚の名前を変える', '棚の名前', s.name);
    if (name == null || name.trim().isEmpty) return;
    s.name = name.trim();
    await AppData.I.save();
    setState(() {});
  }

  Future<void> _deleteShelf(Shelf s) async {
    final ok = await _confirm('棚「${s.name}」を消しますか？\n中の作品は消えず、「棚なし」に移ります。');
    if (ok != true) return;
    for (final w in AppData.I.works) {
      if (w.shelfId == s.id) w.shelfId = '';
    }
    AppData.I.shelves.removeWhere((x) => x.id == s.id);
    await AppData.I.save();
    setState(() {});
  }

  Future<String?> _textDialog(String title, String label, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, decoration: InputDecoration(labelText: label), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('決定')),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('実行する')),
          ],
        ),
      );

  Future<void> _export() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/eigadana_backup.json');
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(AppData.I.encode()));
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('バックアップを書き出しました'),
          content: Text('ファイルの場所:\n${f.path}\n\nこのファイルを控えておくと、「読み込む」で棚と作品の情報を戻せます。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (e) {
      if (mounted) _snack('書き出しに失敗しました: $e');
    }
  }

  Future<void> _import() async {
    final ok = await _confirm('バックアップを読み込むと、今の棚と作品の情報は置き換わります。よろしいですか？');
    if (ok != true) return;
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = r?.files.single.path;
      if (path == null) return;
      final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      AppData.I.decode(j);
      await AppData.I.save();
      if (mounted) {
        _snack('読み込みました');
        setState(() {});
      }
    } catch (e) {
      if (mounted) _snack('読み込みに失敗しました: $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openShelf(String shelfId, String name) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ShelfPage(shelfId: shelfId, shelfName: name)));
    if (mounted) setState(() {});
  }

  Future<void> _openWork(Work w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(work: w)));
    if (mounted) setState(() {});
  }

  Widget _boxCard(String shelfId, String name, {Shelf? shelf}) {
    final list = AppData.I.worksOf(shelfId);
    final unwatched = list.where((w) => !w.watched).length;
    final eps = list.where((w) => w.episode != null).map((w) => w.episode!).toList();
    String range = '';
    if (eps.isNotEmpty) {
      eps.sort();
      range = eps.first == eps.last ? '・第${eps.first}話' : '・第${eps.first}話〜第${eps.last}話';
    }
    final cont = AppData.I.continueWork(shelfId);
    return Card(
      color: kCard,
      child: InkWell(
        onTap: () => _openShelf(shelfId, name),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.video_library, size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
                  if (shelf != null)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rename') _renameShelf(shelf);
                        if (v == 'delete') _deleteShelf(shelf);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('名前を変える')),
                        PopupMenuItem(value: 'delete', child: Text('棚を消す(作品は残る)')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('全${list.length}本・未視聴$unwatched本$range'),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    list.take(3).map((w) => w.title).join('、'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kSub),
                  ),
                ),
              if (cont != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(foregroundColor: kContinue, backgroundColor: kContinueBg),
                    onPressed: () => _openWork(cont),
                    child: Text('▶ つづき${cont.episode != null ? ':第${cont.episode}話' : ':${cont.title}'}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('映画棚')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('もう一度読み込む')),
              ],
            ),
          ),
        ),
      );
    }
    final d = AppData.I;
    List<Work> searchResults = [];
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      searchResults = d.works.where((w) => w.title.toLowerCase().contains(q) || w.fileName.toLowerCase().contains(q)).toList();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('映画棚'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _export();
              if (v == 'import') _import();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('バックアップを書き出す')),
              PopupMenuItem(value: 'import', child: Text('バックアップを読み込む')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kWood,
        foregroundColor: Colors.white,
        onPressed: _newShelf,
        icon: const Icon(Icons.add),
        label: const Text('新しい棚の箱を作る'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'タイトルで探す(全ての棚から)'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Text('作品は全部で${d.works.length}本・棚は${d.shelves.length}箱', style: const TextStyle(color: kSub)),
          const SizedBox(height: 10),
          if (_query.trim().isNotEmpty) ...[
            Text('検索結果: ${searchResults.length}件'),
            const SizedBox(height: 6),
            for (final w in searchResults)
              ListTile(
                leading: const Icon(Icons.movie),
                title: Text(w.title),
                subtitle: Text('${w.episode != null ? '第${w.episode}話・' : ''}${w.fileName}'),
                trailing: w.isInProgress ? const Text('▶ つづき', style: TextStyle(color: kContinue)) : null,
                onTap: () => _openWork(w),
              ),
            if (searchResults.isEmpty) const Text('見つかりませんでした'),
          ] else ...[
            for (final s in d.shelves) _boxCard(s.id, s.name, shelf: s),
            _boxCard('', '棚なし'),
            if (d.shelves.isEmpty && d.works.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('まだ棚も作品もありません。\n「新しい棚の箱を作る」で棚を作って、棚を開いて作品を加えてください。', textAlign: TextAlign.center),
              ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ---------- 棚の中 ----------

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key, required this.shelfId, required this.shelfName});
  final String shelfId; // '' = 棚なし
  final String shelfName;
  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  bool _reorder = false;

  List<Work> get _list => AppData.I.worksOf(widget.shelfId);

  Work _workFromFile(PlatformFile f, String title, int? episode) => Work(
        id: newId(),
        title: title,
        shelfId: widget.shelfId,
        episode: episode,
        fileName: f.name,
        filePath: f.path ?? '',
        fileSizeBytes: f.size,
        sortOrder: AppData.I.nextSortOrder(widget.shelfId),
      );

  Future<void> _addSingle() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: videoExtensions);
    final f = r?.files.single;
    if (f == null) return;
    final titleCtl = TextEditingController(text: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final epCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作品を加える'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(f.name, style: const TextStyle(color: kSub)),
            TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'タイトル')),
            TextField(controller: epCtl, decoration: const InputDecoration(labelText: '話数(空でも可)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加える')),
        ],
      ),
    );
    if (ok != true) return;
    AppData.I.works.add(_workFromFile(f, titleCtl.text.trim().isEmpty ? f.name : titleCtl.text.trim(), int.tryParse(epCtl.text)));
    await AppData.I.save();
    setState(() {});
  }

  Future<void> _addBulk() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: videoExtensions, allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    final files = [...r.files]..sort((a, b) => natCompare(a.name, b.name));
    // 続きから: この棚の最大話数+1、無ければ1
    var start = 1;
    final eps = _list.where((w) => w.episode != null).map((w) => w.episode!).toList();
    if (eps.isNotEmpty) start = eps.reduce((a, b) => a > b ? a : b) + 1;
    final startCtl = TextEditingController(text: '$start');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('まとめて追加(${files.length}件)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: startCtl, decoration: const InputDecoration(labelText: '最初の話数'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              width: 320,
              child: ListView(
                children: [for (var i = 0; i < files.length; i++) Text('${i + 1}. ${files[i].name}', maxLines: 1, overflow: TextOverflow.ellipsis)],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('まとめて加える')),
        ],
      ),
    );
    if (ok != true) return;
    var ep = int.tryParse(startCtl.text) ?? start;
    for (final f in files) {
      AppData.I.works.add(_workFromFile(f, f.name.replaceAll(RegExp(r'\.[^.]+$'), ''), ep));
      ep++;
    }
    await AppData.I.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length}件を追加しました')));
      setState(() {});
    }
  }

  Future<void> _openWork(Work w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(work: w)));
    if (mounted) setState(() {});
  }

  Widget _workCard(Work w) {
    final tileIdx = tileIndexFor(w);
    return Card(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openWork(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 色付きポスター風タイル(Web版の棚と同じ見た目)。
            // 高さはExpandedで残り全部を受けるので、セルより高くなることはない。
            // タイトルは白・太字で中央、左上に話数バッジ、右下に再生マーク。
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [kTilePalette[tileIdx], kTilePaletteDark[tileIdx]],
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text(
                          w.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, height: 1.25),
                        ),
                      ),
                    ),
                    if (w.episode != null)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0x73000000), borderRadius: BorderRadius.circular(8)),
                          child: Text('第${w.episode}話', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: Color(0x73000000), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // タイルの下の情報エリア。どのカードでも同じ高さ(88)にそろえ、
            // ポスターの高さがカードごとに揃うようにする。
            // 中身の最大量(サイズ+つづき一式)は実機で76だと1pxはみ出したため、
            // 88まで広げ、内側の余白と間隔も少し詰めて余裕を持たせてある。
            // 残りの高さはタイル側が受けるので、縦はみ出しは起きない。
            SizedBox(
              height: 88,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtSize(w.fileSizeBytes), style: const TextStyle(color: kSub, fontSize: 12)),
                    if (w.watched) const Text('観た', style: TextStyle(color: kWatched, fontSize: 12)),
                    if (w.isInProgress) ...[
                      const SizedBox(height: 2),
                      const Text('▶ つづき', style: TextStyle(color: kContinue, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 1),
                      SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: w.durationSeconds > 0 ? w.positionSeconds / w.durationSeconds : 0,
                          color: kContinue,
                          backgroundColor: kContinueBg,
                        ),
                      ),
                      const SizedBox(height: 1),
                      // 詳細(経過/残り)は狭いセルで何行にも折り返すと縦に溢れるので1行に制限する
                      Text('つづき ${fmtTime(w.positionSeconds)} / ${fmtTime(w.durationSeconds)}・残り約${fmtTime(w.durationSeconds - w.positionSeconds)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kSub, fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final cont = AppData.I.continueWork(widget.shelfId);
    return Scaffold(
      appBar: AppBar(
        // 棚名が長くても「並び替え」ボタンを押し出さないよう、タイトルは1行で省略する
        title: Text(widget.shelfName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (list.length > 1)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _reorder = !_reorder),
              child: Text(_reorder ? '完了' : '並び替え'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            // 1行に全部並べると狭い画面で右にはみ出すため、Wrapで収まらない分を2行目へ流す
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('全${list.length}本', style: const TextStyle(color: kSub)),
                if (cont != null)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      foregroundColor: kContinue,
                      backgroundColor: kContinueBg,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _openWork(cont),
                    child: Text('▶ つづき${cont.episode != null ? ':第${cont.episode}話' : ''}'),
                  ),
                if (!_reorder) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    onPressed: _addBulk,
                    icon: const Icon(Icons.library_add, size: 18),
                    label: const Text('まとめて追加'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    onPressed: _addSingle,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('追加'),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('この棚はまだ空です。「追加」から動画ファイルを加えてください。'))
                : _reorder
                    ? ReorderableListView.builder(
                        itemCount: list.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) newIndex--;
                          final ordered = AppData.I.worksOf(widget.shelfId);
                          final moved = ordered.removeAt(oldIndex);
                          ordered.insert(newIndex, moved);
                          for (var i = 0; i < ordered.length; i++) {
                            ordered[i].sortOrder = i;
                          }
                          // worksOfは同じオブジェクト参照なのでsortOrderの付け替えで十分
                          await AppData.I.save();
                          setState(() {});
                        },
                        itemBuilder: (ctx, i) {
                          final w = list[i];
                          return ListTile(
                            key: ValueKey(w.id),
                            leading: const Icon(Icons.drag_handle),
                            title: Text('${w.episode != null ? '第${w.episode}話 ' : ''}${w.title}'),
                            subtitle: Text(w.fileName),
                          );
                        },
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 5 : (MediaQuery.of(context).size.width > 600 ? 4 : 3),
                          // カード内(色タイル+下の情報エリア88)が収まるよう、
                          // セルを縦長にする。タイルはExpandedで残り高さに収める。
                          childAspectRatio: 0.55,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => _workCard(list[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------- 詳細・再生 ----------

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.work});
  final Work work;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;
  bool _seeked = false;
  bool _finished = false;
  String? _error;
  bool _fileMissing = false;

  Work get w => widget.work;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (w.filePath.isEmpty || !File(w.filePath).existsSync()) {
      setState(() {
        _fileMissing = true;
        _error = 'ファイルが見つかりません。スマホ側で移動・削除された可能性があります。同じファイルを選び直してください。';
      });
      return;
    }
    _subs.add(_player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty) setState(() => _error = e);
    }));
    _subs.add(_player.stream.duration.listen((d) {
      if (d.inSeconds > 0) {
        w.durationSeconds = d.inSeconds;
        if (!_seeked && w.positionSeconds >= 10 && !w.isAtEnd) {
          _seeked = true;
          _player.seek(Duration(seconds: w.positionSeconds));
        }
      }
    }));
    _subs.add(_player.stream.position.listen((p) {
      w.positionSeconds = p.inSeconds;
      if (!_finished && w.durationSeconds > 0 && w.isAtEnd) {
        _finished = true;
        _markWatched();
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done && !_finished) {
        _finished = true;
        _markWatched();
      }
    }));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => AppData.I.save());
    try {
      await _player.open(Media(Uri.file(w.filePath).toString()));
    } catch (e) {
      if (mounted) {
        setState(() {
          _fileMissing = true;
          _error = 'ファイルを開けませんでした: $e';
        });
      }
    }
  }

  Future<void> _markWatched() async {
    w.watched = true;
    await AppData.I.save();
    if (mounted) setState(() {});
  }

  Future<void> _repick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: videoExtensions);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    w.filePath = f.path!;
    w.fileName = f.name;
    w.fileSizeBytes = f.size;
    await AppData.I.save();
    // 再生し直す
    setState(() {
      _error = null;
      _fileMissing = false;
      _seeked = false;
      _finished = w.watched;
    });
    try {
      await _player.open(Media(Uri.file(w.filePath).toString()));
    } catch (e) {
      if (mounted) setState(() => _error = 'ファイルを開けませんでした: $e');
    }
  }

  Future<void> _edit() async {
    final titleCtl = TextEditingController(text: w.title);
    final epCtl = TextEditingController(text: w.episode?.toString() ?? '');
    final memoCtl = TextEditingController(text: w.memo);
    var rating = w.rating;
    var watched = w.watched;
    var shelfId = w.shelfId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('作品を直す'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'タイトル')),
                TextField(controller: epCtl, decoration: const InputDecoration(labelText: '話数(空でも可)'), keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  value: shelfId,
                  decoration: const InputDecoration(labelText: '置く棚'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('棚なし')),
                    for (final s in AppData.I.shelves) DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setLocal(() => shelfId = v ?? ''),
                ),
                Row(
                  children: [
                    const Text('評価: '),
                    // 星ボタンは既定の48dpだと5個で横にはみ出すため、40dpに詰める。
                    // それでも収まらない狭さの場合はFittedBoxで縮めて保険をかける
                    //(通常の幅では等倍のまま)。
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 1; i <= 5; i++)
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 26,
                                  style: IconButton.styleFrom(
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(40, 40),
                                    maximumSize: const Size(40, 40),
                                    padding: EdgeInsets.zero,
                                  ),
                                  icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: kStar),
                                  onPressed: () => setLocal(() => rating = i == rating ? 0 : i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('観た'),
                  value: watched,
                  onChanged: (v) => setLocal(() => watched = v),
                ),
                TextField(controller: memoCtl, decoration: const InputDecoration(labelText: 'メモ'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final shelfChanged = shelfId != w.shelfId;
    w.title = titleCtl.text.trim().isEmpty ? w.title : titleCtl.text.trim();
    w.episode = int.tryParse(epCtl.text);
    w.memo = memoCtl.text;
    w.rating = rating;
    w.watched = watched;
    if (shelfChanged) {
      w.shelfId = shelfId;
      w.sortOrder = AppData.I.nextSortOrder(shelfId);
    }
    await AppData.I.save();
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('「${w.title}」を棚から外しますか？\nスマホ内の動画ファイル自体は消えません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('外す')),
        ],
      ),
    );
    if (ok != true) return;
    AppData.I.works.removeWhere((x) => x.id == w.id);
    await AppData.I.save();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    AppData.I.save();
    _saveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _fileMissing ? const ColoredBox(color: Colors.black) : Video(controller: _controller),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Card(
                color: kContinueBg,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('再生できません', style: TextStyle(fontWeight: FontWeight.bold, color: kContinue)),
                      const SizedBox(height: 4),
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: _repick, icon: const Icon(Icons.folder_open), label: const Text('ファイルを選び直す')),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (w.episode != null)
                  Text('第${w.episode}話', style: const TextStyle(color: kEpisode, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(w.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${w.fileName}\n${fmtSize(w.fileSizeBytes)}', style: const TextStyle(color: kSub)),
                if (w.durationSeconds > 0) ...[
                  const SizedBox(height: 8),
                  if (w.isInProgress) const Text('▶ つづき', style: TextStyle(color: kContinue, fontWeight: FontWeight.bold)),
                  LinearProgressIndicator(value: w.positionSeconds / w.durationSeconds, color: kContinue, backgroundColor: kContinueBg),
                  Text('${fmtTime(w.positionSeconds)} / ${fmtTime(w.durationSeconds)}'),
                ],
                if (w.rating > 0)
                  Row(children: [for (var i = 1; i <= w.rating; i++) const Icon(Icons.star, color: kStar, size: 20)]),
                if (w.watched) const Text('観た', style: TextStyle(color: kWatched)),
                if (w.memo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w.memo)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!_fileMissing && _error == null)
                      OutlinedButton.icon(onPressed: _repick, icon: const Icon(Icons.folder_open), label: const Text('ファイルを選び直す')),
                    OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit), label: const Text('直す')),
                    OutlinedButton.icon(onPressed: _delete, icon: const Icon(Icons.delete), label: const Text('棚から外す')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

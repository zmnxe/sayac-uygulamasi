import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ==========================================
// YEREL VERİTABANI YÖNETİCİSİ (Sqflite)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sayac_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        apartmentName TEXT NOT NULL,
        barcode TEXT NOT NULL,
        totalAmount REAL,
        date TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertReading(String name, String barcode, double amount) async {
    final db = await instance.database;
    return await db.insert('readings', {
      'apartmentName': name,
      'barcode': barcode,
      'totalAmount': amount,
      'date': DateTime.now().toString(),
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Site Sayaç ve Fatura',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

// ==========================================
// ANA EKRAN & HESAPLAMA MODÜLÜ
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String scannedBarcode = "Henüz barkod okunmadı";
  String apartmentName = "Seçilmedi / Tanımsız Daire";

  // Isınma ve Sıcak Su Endeks Kontrolcüleri
  final TextEditingController heatingFirst = TextEditingController(text: '100');
  final TextEditingController heatingLast = TextEditingController();
  final TextEditingController hotWaterFirst = TextEditingController(text: '50');
  final TextEditingController hotWaterLast = TextEditingController();

  // Birim Fiyat Kontrolcüleri
  final TextEditingController heatingPrice = TextEditingController(text: '3.5');
  final TextEditingController hotWaterPrice = TextEditingController(text: '15.0');

  double calculatedTotal = 0.0;

  void calculate() {
    double hF = double.tryParse(heatingFirst.text) ?? 0;
    double hL = double.tryParse(heatingLast.text) ?? 0;
    double hP = double.tryParse(heatingPrice.text) ?? 0;

    double hwF = double.tryParse(hotWaterFirst.text) ?? 0;
    double hwL = double.tryParse(hotWaterLast.text) ?? 0;
    double hwP = double.tryParse(hotWaterPrice.text) ?? 0;

    setState(() {
      double heatingCost = (hL > hF ? hL - hF : 0) * hP;
      double hotWaterCost = (hwL > hwF ? hwL - hwF : 0) * hwP;
      calculatedTotal = heatingCost + hotWaterCost;
    });
  }

  // PDF Fatura Oluşturma ve Paylaşma
  Future<void> generateAndSavePdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text("SİTE YÖNETİMİ FATURASI", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Text("Daire / Abone: $apartmentName"),
                pw.Text("Sayaç Barkodu: $scannedBarcode"),
                pw.SizedBox(height: 10),
                pw.Text("Toplam Tutar: ${calculatedTotal.toStringAsFixed(2)} TL", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'fatura.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sayaç Okuma ve Fatura')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Barkod ve Kamera Alanı
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text("Okunan Barkod: $scannedBarcode", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text("Daire: $apartmentName", style: const TextStyle(color: Colors.blue, fontSize: 16)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
                        );
                        if (result != null) {
                          setState(() {
                            scannedBarcode = result;
                            apartmentName = "Daire (Barkod: $result)";
                          });
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Kamera ile Sayaç Oku'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Birim Fiyatlar
            Row(
              children: [
                Expanded(child: TextField(controller: heatingPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Isınma Birim Fiyat'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: hotWaterPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'S.Su Birim Fiyat'))),
              ],
            ),
            const SizedBox(height: 20),

            // Isınma Endeksleri
            const Text('Isınma Endeks', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(child: TextField(controller: heatingFirst, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'İlk Endeks'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: heatingLast, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Son Endeks'))),
              ],
            ),
            const SizedBox(height: 15),

            // Sıcak Su Endeksleri
            const Text('Sıcak Su Endeks', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(child: TextField(controller: hotWaterFirst, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'İlk Endeks'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: hotWaterLast, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Son Endeks'))),
              ],
            ),
            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: calculate,
              child: const Text('Faturayı Hesapla'),
            ),
            const SizedBox(height: 15),

            Text(
              'Toplam Tutar: ${calculatedTotal.toStringAsFixed(2)} TL',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 20),

            // Kaydet ve PDF Çıkar Butonları
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await DatabaseHelper.instance.insertReading(apartmentName, scannedBarcode, calculatedTotal);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veritabanına kaydedildi!')));
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Kaydet'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: generateAndSavePdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF / Fatura Çıkar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// KAMERA & BARKOD TARAYICI EKRANI
// ==========================================
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  CameraController? _controller;
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _isScanning = false;
  List<CameraDescription>? _cameras;

  @override
  void initState() {
    super.initState();
    _initCam();
  }

  Future<void> _initCam() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _controller = CameraController(_cameras![0], ResolutionPreset.high, enableAudio: false);
        await _controller?.initialize();
        _controller?.startImageStream(_processImage);
        setState(() {});
      }
    } catch (e) {
      if (kDebugMode) print(e);
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isScanning) return;
    _isScanning = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage != null) {
        final barcodes = await _barcodeScanner.processImage(inputImage);
        if (barcodes.isNotEmpty) {
          final code = barcodes.first.rawValue;
          if (code != null && mounted) {
            Navigator.pop(context, code);
            return;
          }
        }
      }
    } finally {
      _isScanning = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameras == null) return null;
    final camera = _cameras![0];
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final bytes = Uint8List.fromList(image.planes.fold<List<int>>([], (p, n) => p..addAll(n.bytes)));
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Barkodu Okutun')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Center(
            child: Container(
              width: 250,
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 3)),
            ),
          ),
        ],
      ),
    );
  }
}

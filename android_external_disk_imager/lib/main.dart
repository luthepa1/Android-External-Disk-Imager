import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android External Disk Imager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _bootImageController = TextEditingController();
  final TextEditingController _systemImageController = TextEditingController();
  final TextEditingController _vendorImageController = TextEditingController();

  bool _isBootImageEnabled = true;
  bool _isSystemImageEnabled = true;
  bool _isVendorImageEnabled = true;
  bool _createUserPartition = false;

  Future<void> _selectFile(TextEditingController controller) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['img'],
    );

    if (result != null) {
      setState(() {
        controller.text = result.files.single.path!;
      });
    }
  }

  Widget _buildImageField(String label, TextEditingController controller, bool isEnabled, Function(bool?) onCheckboxChanged) {
    return Row(
      children: [
        Checkbox(
          value: isEnabled,
          onChanged: onCheckboxChanged,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              TextField(
                controller: controller,
                enabled: isEnabled,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: isEnabled ? () => _selectFile(controller) : null,
          child: Text('Select'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Android External Disk Imager'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageField('Boot Image', _bootImageController, _isBootImageEnabled, (value) {
              setState(() => _isBootImageEnabled = value!);
            }),
            SizedBox(height: 16),
            _buildImageField('System Image', _systemImageController, _isSystemImageEnabled, (value) {
              setState(() => _isSystemImageEnabled = value!);
            }),
            SizedBox(height: 16),
            _buildImageField('Vendor Image', _vendorImageController, _isVendorImageEnabled, (value) {
              setState(() => _isVendorImageEnabled = value!);
            }),
            SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _createUserPartition,
                  onChanged: (value) {
                    setState(() => _createUserPartition = value!);
                  },
                ),
                Text('Create user partition?'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

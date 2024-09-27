import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
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

  String? _lastKnownDirectory;
  String? _selectedDrive;

  @override
  void initState() {
    super.initState();
    _loadSavedStates();
  }

  Future<void> _loadSavedStates() async {
    _lastKnownDirectory = prefs.getString('last_known_directory');
    _isBootImageEnabled = prefs.getBool('is_boot_image_enabled') ?? true;
    _isSystemImageEnabled = prefs.getBool('is_system_image_enabled') ?? true;
    _isVendorImageEnabled = prefs.getBool('is_vendor_image_enabled') ?? true;
    
    _loadTextField('boot_image_path', _bootImageController);
    _loadTextField('system_image_path', _systemImageController);
    _loadTextField('vendor_image_path', _vendorImageController);

    setState(() {});
  }

  void _loadTextField(String key, TextEditingController controller) {
    String? savedPath = prefs.getString(key);
    if (savedPath != null && File(savedPath).existsSync()) {
      controller.text = savedPath;
    }
  }

  Future<void> _saveState(String key, bool value) async {
    await prefs.setBool(key, value);
  }

  Future<void> _saveTextField(String key, String value) async {
    if (value.isNotEmpty && File(value).existsSync()) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _selectFile(TextEditingController controller, String prefKey) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['img'],
      initialDirectory: _lastKnownDirectory,
    );

    if (result != null) {
      String filePath = result.files.single.path!;
      setState(() {
        controller.text = filePath;
      });

      // Save the selected file path
      _saveTextField(prefKey, filePath);

      // Save the last known directory
      String directory = filePath.substring(0, filePath.lastIndexOf('/'));
      await prefs.setString('last_known_directory', directory);
      _lastKnownDirectory = directory;
    }
  }

  Widget _buildImageField(String label, TextEditingController controller, bool isEnabled, Function(bool?) onChanged, String prefKey) {
    return Row(
      children: [
        Checkbox(
          value: isEnabled,
          onChanged: (bool? value) {
            onChanged(value);
            _saveState('is_${label.toLowerCase().replaceAll(' ', '_')}_enabled', value ?? false);
          },
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
                onChanged: (value) => _saveTextField(prefKey, value),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: isEnabled ? () => _selectFile(controller, prefKey) : null,
          child: Text('Select'),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _getDrives(bool showAllDrives) async {
    try {
      final result = await Process.run('lsblk', ['-nJo', 'NAME,SIZE,TYPE,MOUNTPOINT,LABEL,FSTYPE,TRAN']);
      if (result.exitCode != 0) {
        print('Error running lsblk: ${result.stderr}');
        return [];
      }

      final Map<String, dynamic> lsblkOutput = json.decode(result.stdout);
      final List<dynamic> blockdevices = lsblkOutput['blockdevices'];

      final drives = blockdevices.where((device) {
        if (device['type'] != 'disk') return false;
        if (showAllDrives) return true;
        // Filter for USB and SD card drives
        return device['tran'] == 'usb' || device['tran'] == 'mmc';
      }).map((device) {
        final List<Map<String, dynamic>> partitions = (device['children'] as List<dynamic>?)
            ?.where((child) => child['type'] == 'part')
            .map((child) => {
                  'name': child['name'],
                  'size': child['size'],
                  'label': child['label'] ?? 'N/A',
                  'fstype': child['fstype'] ?? 'N/A',
                  'mountpoint': child['mountpoint'] ?? 'Not mounted',
                })
            .toList() ?? [];

        return {
          'name': '/dev/${device['name']}',
          'size': device['size'],
          'partitions': partitions,
        };
      }).toList();

      print('Parsed drives: $drives'); // Debug print
      return drives;
    } catch (e) {
      print('Exception in _getDrives: $e');
      return [];
    }
  }

  void _showDriveSelectionDialog() {
    bool showAllDrives = false;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Select a Drive'),
              content: Container(
                width: double.maxFinite,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _getDrives(showAllDrives),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Text('No drives found');
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: showAllDrives,
                              onChanged: (value) {
                                setState(() {
                                  showAllDrives = value!;
                                });
                              },
                            ),
                            Text('Show all drives'),
                          ],
                        ),
                        if (showAllDrives)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'WARNING: Be careful not to select a system drive. All risk is on the user!',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ),
                        SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.length,
                            itemBuilder: (context, index) {
                              final drive = snapshot.data![index];
                              return ExpansionTile(
                                title: Text('${drive['name']} (${drive['size']})'),
                                children: [
                                  Container(
                                    color: Colors.blue[50],
                                    child: ListTile(
                                      title: Text(
                                        'Select this drive',
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).pop(drive['name']);
                                      },
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                  ),
                                  ...(drive['partitions'] as List<Map<String, dynamic>>).map<Widget>((partition) {
                                    return ListTile(
                                      title: Text('${partition['name']} (${partition['size']})'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Label: ${partition['label']}'),
                                          Text('Filesystem: ${partition['fstype']}'),
                                          Text('Mountpoint: ${partition['mountpoint']}'),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    ).then((selectedDrive) {
      if (selectedDrive != null) {
        setState(() {
          _selectedDrive = selectedDrive;
        });
      }
    });
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
            ElevatedButton(
              onPressed: _showDriveSelectionDialog,
              child: Text('Select Drive'),
            ),
            SizedBox(height: 8),
            Text('Selected Drive: ${_selectedDrive ?? "None"}'),
            SizedBox(height: 16),
            _buildImageField('Boot Image', _bootImageController, _isBootImageEnabled, (value) {
              setState(() => _isBootImageEnabled = value!);
            }, 'boot_image_path'),
            SizedBox(height: 16),
            _buildImageField('System Image', _systemImageController, _isSystemImageEnabled, (value) {
              setState(() => _isSystemImageEnabled = value!);
            }, 'system_image_path'),
            SizedBox(height: 16),
            _buildImageField('Vendor Image', _vendorImageController, _isVendorImageEnabled, (value) {
              setState(() => _isVendorImageEnabled = value!);
            }, 'vendor_image_path'),
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

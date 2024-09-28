import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      themeMode: ThemeMode.system,
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.blue,
        colorScheme: const ColorScheme.light(primary: Colors.blue),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[200],
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        colorScheme: const ColorScheme.dark(primary: Colors.blue),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[800],
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class ColoredMessage {
  final String text;
  final Color color;

  ColoredMessage(this.text, this.color);
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
  final TextEditingController _sudoPasswordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isBootImageEnabled = true;
  bool _isSystemImageEnabled = true;
  bool _isVendorImageEnabled = true;
  bool _formatUserPartition = false;
  bool _showPersistentMessages = false;
  bool _isOperationInProgress = false;

  String? _lastKnownDirectory;
  String? _selectedDrive;
  final List<ColoredMessage> _persistentMessages = [];
  String? _sudoPassword;

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
    _formatUserPartition = prefs.getBool('format_user_partition') ?? false;
    
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Checkbox(
          value: isEnabled,
          onChanged: (bool? value) {
            onChanged(value);
            _saveState('is_${label.toLowerCase().replaceAll(' ', '_')}_enabled', value ?? false);
            setState(() {}); // Trigger rebuild to update button state
          },
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              TextField(
                controller: controller,
                enabled: isEnabled,
                decoration: InputDecoration(
                  hintText: 'Select ${label.toLowerCase()} file',
                ),
                onChanged: (value) {
                  _saveTextField(prefKey, value);
                  setState(() {}); // Trigger rebuild to update button state
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: isEnabled ? () => _selectFile(controller, prefKey) : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
          ),
          child: const Text('Select'),
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

      print('Parsed drives: $drives');
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
              title: const Text('Select a Drive'),
              content: SizedBox(
                width: double.maxFinite,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _getDrives(showAllDrives),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No drives found');
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
                            const Text('Show all drives'),
                          ],
                        ),
                        if (showAllDrives)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'WARNING: Be careful not to select a system drive. All risk is on the user!',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 10),
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
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Future<bool> _verifySudoPassword(String password) async {
    try {
      final process = await Process.start('sudo', ['-S', 'true']);
      process.stdin.writeln(password);
      final exitCode = await process.exitCode;
      return exitCode == 0;
    } catch (e) {
      print('Error verifying sudo password: $e');
      return false;
    }
  }

  Future<bool> _requestSudoPermissions() async {
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sudo Permissions Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please enter your sudo password to proceed with disk operations.'),
              const SizedBox(height: 16),
              RawKeyboardListener(
                focusNode: FocusNode(),
                onKey: (RawKeyEvent event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.enter) {
                      _confirmSudoPassword(context);
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop(false);
                    }
                  }
                },
                child: TextField(
                  controller: _sudoPasswordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Sudo Password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Text('Confirm'),
              onPressed: () => _confirmSudoPassword(context),
            ),
          ],
        );
      },
    );

    _sudoPasswordController.clear();
    return result ?? false;
  }

  void _confirmSudoPassword(BuildContext context) async {
    String password = _sudoPasswordController.text;
    bool isValid = await _verifySudoPassword(password);
    if (isValid) {
      _sudoPassword = password;
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect sudo password. Please try again.', style: TextStyle(color: Colors.red))),
      );
    }
  }

  Stream<String> _executeCommand(String command, {bool requireSudo = false}) async* {
    if (requireSudo && _sudoPassword == null) {
      throw Exception('Sudo password not provided for a command requiring sudo.');
    }

    print('Executing command: ${requireSudo ? "sudo " : ""}$command');
    
    late Process process;
    try {
      if (requireSudo) {
        process = await Process.start('sudo', ['-S', 'sh', '-c', command]);
        process.stdin.writeln(_sudoPassword);
      } else {
        process = await Process.start('sh', ['-c', command]);
      }

      await for (var event in process.stdout.transform(utf8.decoder)) {
        yield event;
      }

      await for (var event in process.stderr.transform(utf8.decoder)) {
        yield event;
      }

      final exitCode = await process.exitCode;
      yield 'Exit code: $exitCode';
    } catch (e) {
      yield 'Error executing command: $e';
    }
  }

  Future<bool> _checkDrivePartitions(String drive) async {
    try {
      bool isValid = true;
      await for (var output in _executeCommand('lsblk -nJo NAME,SIZE,FSTYPE,LABEL $drive')) {
        if (output.contains('Error')) {
          print('Error checking drive partitions: $output');
          isValid = false;
          break;
        }
      }

      if (!isValid) return false;

      final result = await Process.run('lsblk', ['-nJo', 'NAME,SIZE,FSTYPE,LABEL', drive]);
      if (result.exitCode != 0) {
        print('Error checking drive partitions: ${result.stderr}');
        return false;
      }

      final Map<String, dynamic> driveInfo = json.decode(result.stdout);
      final List<dynamic> partitions = driveInfo['blockdevices'][0]['children'] ?? [];

      if (partitions.length != 4) return false;

      final bootPartition = partitions[0];
      final systemPartition = partitions[1];
      final vendorPartition = partitions[2];
      final userDataPartition = partitions[3];

      return bootPartition['size'] == '128M' &&
             bootPartition['fstype'] == 'vfat' &&
             bootPartition['label'] == 'boot' &&
             systemPartition['size'] == '2G' &&
             systemPartition['fstype'] == 'ext4' &&
             systemPartition['label'] == '/' &&
             vendorPartition['size'] == '256M' &&
             vendorPartition['fstype'] == 'ext4' &&
             vendorPartition['label'] == 'vendor' &&
             userDataPartition['fstype'] == 'ext4' &&
             userDataPartition['label'] == 'userdata';
    } catch (e) {
      print('Exception in _checkDrivePartitions: $e');
      return false;
    }
  }

  Future<bool> _repartitionDrive(String drive) async {
    try {
      // Unmount all partitions
      await for (var output in _executeCommand('umount $drive*', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }

      // Create new partition table
      await for (var output in _executeCommand('parted -s $drive mklabel gpt', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }

      // Create partitions
      await for (var output in _executeCommand('parted -s $drive mkpart primary fat32 1MiB 129MiB', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 129MiB 2177MiB', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 2177MiB 2433MiB', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 2433MiB 100%', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }

      // Format partitions
      await for (var output in _executeCommand('mkfs.vfat -n "boot" ${drive}1', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('mkfs.ext4 -L "/" ${drive}2', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('mkfs.ext4 -L "vendor" ${drive}3', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }
      await for (var output in _executeCommand('mkfs.ext4 -F -L "userdata" ${drive}4', requireSudo: true)) {
        _showMessage(output, color: Colors.yellow);
      }

      return true;
    } catch (e) {
      print('Error repartitioning drive: $e');
      return false;
    }
  }

  void _showMessage(String message, {Color color = Colors.black}) {
    setState(() {
      _persistentMessages.add(ColoredMessage(message, color));
    });
    if (_showPersistentMessages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: TextStyle(color: color))),
      );
    }
  }

  void _clearPersistentMessages() {
    setState(() {
      _persistentMessages.clear();
    });
  }

  bool _isBurnToDiskEnabled() {
    bool atLeastOneImageSelected = (_isBootImageEnabled && _bootImageController.text.isNotEmpty) ||
                                   (_isSystemImageEnabled && _systemImageController.text.isNotEmpty) ||
                                   (_isVendorImageEnabled && _vendorImageController.text.isNotEmpty);
    return _selectedDrive != null && atLeastOneImageSelected && !_isOperationInProgress;
  }

  void _burnToDisk() async {
    if (!_isBurnToDiskEnabled()) {
      _showMessage('Please select a drive and at least one image to burn.', color: Colors.red);
      return;
    }

    setState(() {
      _isOperationInProgress = true;
    });

    bool sudoGranted = await _requestSudoPermissions();
    if (!sudoGranted) {
      _showMessage('Sudo permissions are required to perform disk operations.', color: Colors.red);
      setState(() {
        _isOperationInProgress = false;
      });
      return;
    }

    _showMessage('Checking drive partitions...', color: Colors.yellow);
    bool partitionsOk = await _checkDrivePartitions(_selectedDrive!);
    if (!partitionsOk) {
      bool confirmRepartition = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Repartition Required'),
            content: const Text('The selected drive does not meet the required partition structure. Do you want to repartition the drive? This will erase all data on the drive and format all partitions, including the user partition.'),
            actions: <Widget>[
              TextButton(
                child: const Text('No'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: const Text('Yes'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (confirmRepartition) {
        _showMessage('Repartitioning drive...', color: Colors.yellow);
        bool repartitionSuccess = await _repartitionDrive(_selectedDrive!);
        if (!repartitionSuccess) {
          _showMessage('Failed to repartition the drive. Please try again.', color: Colors.red);
          setState(() {
            _isOperationInProgress = false;
          });
          return;
        }
        _showMessage('Drive repartitioned successfully.', color: Colors.green);
        partitionsOk = true;
      } else {
        _showMessage('Cannot proceed without proper partition structure.', color: Colors.red);
        setState(() {
          _isOperationInProgress = false;
        });
        return;
      }
    }

    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmation'),
          content: const Text('Are you sure you want to write/modify the selected disk? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirm) {
      if (_isBootImageEnabled && _bootImageController.text.isNotEmpty) {
        _showMessage('Writing boot image to partition 1...', color: Colors.yellow);
        await for (var output in _executeCommand(
          'dd if=${_bootImageController.text} of=${_selectedDrive}1 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output, color: Colors.yellow);
        }
        _showMessage('Boot image written successfully.', color: Colors.green);
      }

      if (_isSystemImageEnabled && _systemImageController.text.isNotEmpty) {
        _showMessage('Writing system image to partition 2...', color: Colors.yellow);
        await for (var output in _executeCommand(
          'dd if=${_systemImageController.text} of=${_selectedDrive}2 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output, color: Colors.yellow);
        }
        _showMessage('System image written successfully.', color: Colors.green);
      }

      if (_isVendorImageEnabled && _vendorImageController.text.isNotEmpty) {
        _showMessage('Writing vendor image to partition 3...', color: Colors.yellow);
        await for (var output in _executeCommand(
          'dd if=${_vendorImageController.text} of=${_selectedDrive}3 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output, color: Colors.yellow);
        }
        _showMessage('Vendor image written successfully.', color: Colors.green);
      }
      
      if (_formatUserPartition && !partitionsOk) {
        _showMessage('Formatting user partition 4...', color: Colors.yellow);
        await for (var output in _executeCommand(
          'mkfs.ext4 -F -L "userdata" ${_selectedDrive}4',
          requireSudo: true,
        )) {
          _showMessage(output, color: Colors.yellow);
        }
        _showMessage('User partition formatted successfully.', color: Colors.green);
      }
      
      _showMessage('All operations completed successfully.', color: Colors.green);
    }

    // Clear sudo password after operations are complete
    _sudoPassword = null;
    setState(() {
      _isOperationInProgress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android External Disk Imager'),
      ),
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height - 80, // Subtract AppBar height
          ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                ElevatedButton(
                  onPressed: _showDriveSelectionDialog,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text('Select Drive'),
                ),
                const SizedBox(height: 8),
                Text('Selected Drive: ${_selectedDrive ?? "None"}'),
                const SizedBox(height: 16),
                _buildImageField('Boot Image', _bootImageController, _isBootImageEnabled, (value) {
                  setState(() => _isBootImageEnabled = value!);
                }, 'boot_image_path'),
                const SizedBox(height: 16),
                _buildImageField('System Image', _systemImageController, _isSystemImageEnabled, (value) {
                  setState(() => _isSystemImageEnabled = value!);
                }, 'system_image_path'),
                const SizedBox(height: 16),
                _buildImageField('Vendor Image', _vendorImageController, _isVendorImageEnabled, (value) {
                  setState(() => _isVendorImageEnabled = value!);
                }, 'vendor_image_path'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _formatUserPartition,
                      onChanged: (value) {
                        setState(() {
                          _formatUserPartition = value!;
                          _saveState('format_user_partition', value);
                        });
                      },
                    ),
                    const Expanded(child: Text('Format user partition (if not repartitioning)')),
                  ],
                ),
                const Text('Note: User partition will always be formatted during repartitioning.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isBurnToDiskEnabled() ? _burnToDisk : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: _isOperationInProgress
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Burn to disk'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Show persistent messages'),
                    Switch(
                      value: _showPersistentMessages,
                      onChanged: (value) {
                        setState(() {
                          _showPersistentMessages = value;
                        });
                      },
                    ),
                  ],
                ),
                if (_showPersistentMessages) ...[
                  const SizedBox(height: 16),
                  const Text('Messages:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[850], // Dark background for better contrast
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _persistentMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            _persistentMessages[index].text,
                            style: TextStyle(
                              color: _persistentMessages[index].color,
                              fontWeight: FontWeight.bold, // Make text bold for better visibility
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _clearPersistentMessages,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                      ),
                      child: const Text('Clear Messages'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

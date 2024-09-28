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
      home: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight + 200, // Increase height by 200 pixels
            child: const HomePage(),
          );
        },
      ),
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
  final TextEditingController _sudoPasswordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isBootImageEnabled = true;
  bool _isSystemImageEnabled = true;
  bool _isVendorImageEnabled = true;
  bool _formatUserPartition = false;
  bool _showPersistentMessages = false; // Always initialized to false
  bool _isOperationInProgress = false;

  String? _lastKnownDirectory;
  String? _selectedDrive;
  List<String> _persistentMessages = [];
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
    // Removed loading of _showPersistentMessages
    
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
            setState(() {}); // Trigger rebuild to update button state
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
                onChanged: (value) {
                  _saveTextField(prefKey, value);
                  setState(() {}); // Trigger rebuild to update button state
                },
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

  Future<bool> _requestSudoPermissions() async {
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sudo Permissions Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please enter your sudo password to proceed with disk operations.'),
              SizedBox(height: 16),
              TextField(
                controller: _sudoPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Sudo Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: Text('Confirm'),
              onPressed: () {
                _sudoPassword = _sudoPasswordController.text;
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    _sudoPasswordController.clear();
    return result ?? false;
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
      await for (var output in _executeCommand('umount ${drive}*', requireSudo: true)) {
        _showMessage(output);
      }

      // Create new partition table
      await for (var output in _executeCommand('parted -s $drive mklabel gpt', requireSudo: true)) {
        _showMessage(output);
      }

      // Create partitions
      await for (var output in _executeCommand('parted -s $drive mkpart primary fat32 1MiB 129MiB', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 129MiB 2177MiB', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 2177MiB 2433MiB', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('parted -s $drive mkpart primary ext4 2433MiB 100%', requireSudo: true)) {
        _showMessage(output);
      }

      // Format partitions
      await for (var output in _executeCommand('mkfs.vfat -n "boot" ${drive}1', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('mkfs.ext4 -L "/" ${drive}2', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('mkfs.ext4 -L "vendor" ${drive}3', requireSudo: true)) {
        _showMessage(output);
      }
      await for (var output in _executeCommand('mkfs.ext4 -F -L "userdata" ${drive}4', requireSudo: true)) {
        _showMessage(output);
      }

      return true;
    } catch (e) {
      print('Error repartitioning drive: $e');
      return false;
    }
  }

  void _showMessage(String message) {
    setState(() {
      _persistentMessages.add(message);
    });
    if (_showPersistentMessages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
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
      _showMessage('Please select a drive and at least one image to burn.');
      return;
    }

    setState(() {
      _isOperationInProgress = true;
    });

    bool sudoGranted = await _requestSudoPermissions();
    if (!sudoGranted) {
      _showMessage('Sudo permissions are required to perform disk operations.');
      setState(() {
        _isOperationInProgress = false;
      });
      return;
    }

    _showMessage('Checking drive partitions...');
    bool partitionsOk = await _checkDrivePartitions(_selectedDrive!);
    if (!partitionsOk) {
      bool confirmRepartition = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Repartition Required'),
            content: Text('The selected drive does not meet the required partition structure. Do you want to repartition the drive? This will erase all data on the drive and format all partitions, including the user partition.'),
            actions: <Widget>[
              TextButton(
                child: Text('No'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text('Yes'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (confirmRepartition) {
        _showMessage('Repartitioning drive...');
        bool repartitionSuccess = await _repartitionDrive(_selectedDrive!);
        if (!repartitionSuccess) {
          _showMessage('Failed to repartition the drive. Please try again.');
          setState(() {
            _isOperationInProgress = false;
          });
          return;
        }
        _showMessage('Drive repartitioned successfully.');
        partitionsOk = true;
      } else {
        _showMessage('Cannot proceed without proper partition structure.');
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
          title: Text('Confirmation'),
          content: Text('Are you sure you want to write/modify the selected disk? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: Text('No'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text('Yes'),
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
        _showMessage('Writing boot image to partition 1...');
        await for (var output in _executeCommand(
          'dd if=${_bootImageController.text} of=${_selectedDrive}1 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output);
        }
      }

      if (_isSystemImageEnabled && _systemImageController.text.isNotEmpty) {
        _showMessage('Writing system image to partition 2...');
        await for (var output in _executeCommand(
          'dd if=${_systemImageController.text} of=${_selectedDrive}2 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output);
        }
      }

      if (_isVendorImageEnabled && _vendorImageController.text.isNotEmpty) {
        _showMessage('Writing vendor image to partition 3...');
        await for (var output in _executeCommand(
          'dd if=${_vendorImageController.text} of=${_selectedDrive}3 bs=4M status=progress',
          requireSudo: true,
        )) {
          _showMessage(output);
        }
      }
      
      if (_formatUserPartition && !partitionsOk) {
        _showMessage('Formatting user partition 4...');
        await for (var output in _executeCommand(
          'mkfs.ext4 -F -L "userdata" ${_selectedDrive}4',
          requireSudo: true,
        )) {
          _showMessage(output);
        }
      }
      
      _showMessage('All operations completed.');
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
        title: Text('Android External Disk Imager'),
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
                      value: _formatUserPartition,
                      onChanged: (value) {
                        setState(() {
                          _formatUserPartition = value!;
                          _saveState('format_user_partition', value);
                        });
                      },
                    ),
                    Expanded(child: Text('Format user partition (if not repartitioning)')),
                  ],
                ),
                Text('Note: User partition will always be formatted during repartitioning.'),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isBurnToDiskEnabled() ? _burnToDisk : null,
                  child: _isOperationInProgress
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Burn to disk'),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Show persistent messages'),
                    Switch(
                      value: _showPersistentMessages,
                      onChanged: (value) {
                        setState(() {
                          _showPersistentMessages = value;
                          // Removed saving of _showPersistentMessages
                        });
                      },
                    ),
                  ],
                ),
                if (_showPersistentMessages) ...[
                  SizedBox(height: 16),
                  Text('Messages:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _persistentMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(_persistentMessages[index]),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _clearPersistentMessages,
                    child: Text('Clear Messages'),
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

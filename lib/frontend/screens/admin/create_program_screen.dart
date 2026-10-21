import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../../security/input_validator.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/media_widgets.dart';

class CreateProgramScreen extends StatefulWidget {
  final Program? programToEdit;

  const CreateProgramScreen({super.key, this.programToEdit});

  @override
  State<CreateProgramScreen> createState() => _CreateProgramScreenState();
}

class _CreateProgramScreenState extends State<CreateProgramScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final String _programId;
  late DateTime _date;
  late TimeOfDay _time;
  String _category = 'Academic';
  String _status = 'open';
  String _coverMediaId = '';
  List<MediaRef> _gallery = [];
  final Set<String> _uploadedThisSession = {};
  final Set<String> _removed = {};
  bool _saving = false;
  bool _saved = false;
  bool _uploading = false;
  late final AdminState _adminState;

  bool get _isEditing => widget.programToEdit != null;

  @override
  void initState() {
    super.initState();
    final program = widget.programToEdit;
    _adminState = context.read<AdminState>();
    _programId = program?.id ?? _adminState.programsRepo.newProgramId();
    _title = TextEditingController(text: program?.title ?? '');
    _description = TextEditingController(text: program?.description ?? '');
    _location = TextEditingController(text: program?.location ?? '');
    _capacity = TextEditingController(text: '${program?.capacity ?? 50}');
    _date = DateTime.tryParse(program?.date ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    _time = _parseTime(program?.time) ?? const TimeOfDay(hour: 9, minute: 0);
    _category = program?.category ?? 'Academic';
    _status = program?.status ?? 'open';
    _coverMediaId = program?.coverMediaId ?? '';
    _gallery = [...?program?.gallery];
  }

  @override
  void dispose() {
    // Buang media yang dimuat naik tetapi borang tidak disimpan (elak yatim).
    if (!_saved && _uploadedThisSession.isNotEmpty) {
      for (final id in _uploadedThisSession) {
        _adminState.media.delete(id).catchError((_) {});
      }
    }
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _capacity.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    return TimeOfDay(
      hour: int.tryParse(match.group(1)!)?.clamp(0, 23) ?? 9,
      minute: int.tryParse(match.group(2)!)?.clamp(0, 59) ?? 0,
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  // ------------------------------------------------------------------ media

  Future<void> _addImage({bool asCover = false}) async {
    final state = context.read<AdminState>();
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final item = await state.uploadImage(bytes, programId: _programId);
      _uploadedThisSession.add(item.id);
      setState(() {
        _gallery = [..._gallery, item.toRef()];
        if (asCover || _coverMediaId.isEmpty) _coverMediaId = item.id;
      });
      if (mounted) {
        showSnack(context, 'Image uploaded (${formatBytes(item.sizeBytes)} after compression).');
      }
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addVideo() async {
    final values = await showTextFieldsDialog(
      context,
      title: 'Add video link',
      intro: 'Upload the video to YouTube (Unlisted) or Google Drive, then paste the share link here.',
      fields: const [
        DialogField(
          label: 'https:// link',
          keyboardType: TextInputType.url,
          validator: InputValidator.validateVideoUrl,
        ),
        DialogField(label: 'Caption (optional)', maxLength: 200),
      ],
      confirmLabel: 'Add',
    );
    if (values == null || !mounted) return;
    final state = context.read<AdminState>();
    try {
      setState(() => _uploading = true);
      final item = await state.addVideoLink(
        values[0].trim(),
        programId: _programId,
        caption: values[1].trim(),
      );
      _uploadedThisSession.add(item.id);
      setState(() => _gallery = [..._gallery, item.toRef()]);
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeMedia(MediaRef ref) {
    setState(() {
      _gallery = _gallery.where((m) => m.id != ref.id).toList();
      _removed.add(ref.id);
      if (_coverMediaId == ref.id) {
        _coverMediaId = _gallery.firstWhere(
          (m) => m.isImage,
          orElse: () => const MediaRef(id: '', kind: 'image'),
        ).id;
      }
    });
  }

  // ------------------------------------------------------------------ save

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final capacity = int.parse(_capacity.text.trim());
    final current = widget.programToEdit;
    if (current != null && capacity < current.joinedCount) {
      showSnack(
        context,
        'Capacity cannot be lower than ${current.joinedCount} joined students.',
        error: true,
      );
      return;
    }

    setState(() => _saving = true);
    final state = context.read<AdminState>();
    final program = Program(
      id: _programId,
      title: _title.text.trim(),
      description: _description.text.trim(),
      date: _date.toIso8601String().split('T').first,
      time: '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      location: _location.text.trim(),
      capacity: capacity,
      category: _category,
      status: _status,
      cancellationReason: current?.cancellationReason ?? '',
      coverMediaId: _coverMediaId,
      gallery: _gallery,
      seatShards: current?.seatShards ?? 0,
      createdBy: current?.createdBy ?? '',
      joinedCount: current?.joinedCount ?? 0,
    );

    try {
      var message = '';
      if (current != null) {
        final notified = await state.updateProgram(program, previous: current);
        message = notified > 0
            ? 'Program updated. $notified participants notified and emails queued.'
            : 'Program updated.';
      } else {
        await state.createProgram(program);
        message = _status == 'draft'
            ? 'Program saved as draft.'
            : 'Program published to the Student App.';
      }
      _saved = true;
      for (final id in _removed) {
        state.deleteMedia(id).catchError((_) {});
      }
      if (!mounted) return;
      showSnack(context, message);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showSnack(context, 'Program could not be saved. ${friendlyError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusOptions = _isEditing
        ? Program.statuses.where((value) => value != 'cancelled').toList()
        : const ['draft', 'open'];
    if (!statusOptions.contains(_status)) _status = statusOptions.first;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit program' : 'New program')),
      body: PageBackdrop(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text(
                _isEditing ? 'Refine the details.' : 'Build something worth joining.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                _isEditing
                    ? 'Changing the date, time or location notifies joined students and queues parent emails.'
                    : 'Drafts stay private. Open programs appear immediately in the Student App.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Program details', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const Key('program_title'),
                        controller: _title,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Program title',
                          prefixIcon: Icon(Icons.title_rounded),
                        ),
                        validator: (value) => InputValidator.validateRequired(value, 'Title'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('program_description'),
                        controller: _description,
                        minLines: 4,
                        maxLines: 7,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) => InputValidator.validateRequired(
                          value,
                          'Description',
                          maxLength: 4000,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: Program.categories
                            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _category = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Images & videos', style: Theme.of(context).textTheme.titleLarge),
                          ),
                          if (_uploading)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Images are compressed and stored in Firestore (max ~900 KB each). Videos are added as YouTube/Drive links.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      if (_coverMediaId.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: FirestoreImage(mediaId: _coverMediaId),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Cover image', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                      ],
                      MediaGallery(media: _gallery, onDelete: _removeMedia),
                      if (_gallery.isNotEmpty) const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _uploading ? null : () => _addImage(asCover: true),
                            icon: const Icon(Icons.wallpaper_rounded),
                            label: const Text('Set cover'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _uploading ? null : _addImage,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Add image'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _uploading ? null : _addVideo,
                            icon: const Icon(Icons.video_library_outlined),
                            label: const Text('Add video link'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Schedule & access', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _PickerField(
                              label: 'Date',
                              value: formatProgramDate(_date.toIso8601String().split('T').first),
                              icon: Icons.calendar_month_rounded,
                              onTap: _pickDate,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PickerField(
                              label: 'Time',
                              value: _time.format(context),
                              icon: Icons.schedule_rounded,
                              onTap: _pickTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('program_location'),
                        controller: _location,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (value) =>
                            InputValidator.validateRequired(value, 'Location', maxLength: 200),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('program_capacity'),
                              controller: _capacity,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Capacity',
                                prefixIcon: Icon(Icons.groups_2_outlined),
                              ),
                              validator: (value) {
                                final number = int.tryParse(value ?? '');
                                if (number == null || number < 1) return 'Enter 1 or more';
                                if (number > 5000) return 'Maximum 5000';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _status,
                              decoration: const InputDecoration(labelText: 'Status'),
                              items: statusOptions
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(StatusPill.statusLabel(value)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _status = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: FilledButton.icon(
            key: const Key('program_save'),
            style: FilledButton.styleFrom(
              backgroundColor: _status == 'draft'
                  ? AppTheme.violet
                  : _isEditing
                  ? AppTheme.cobalt
                  : AppTheme.coral,
            ),
            onPressed: _saving || _uploading ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Icon(_status == 'draft' ? Icons.save_outlined : Icons.publish_rounded),
            label: Text(
              _saving
                  ? 'Saving...'
                  : _isEditing
                  ? 'SAVE CHANGES'
                  : _status == 'draft'
                  ? 'SAVE DRAFT'
                  : 'PUBLISH PROGRAM',
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

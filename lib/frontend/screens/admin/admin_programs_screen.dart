import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'program_detail_admin.dart';

class AdminProgramsScreen extends StatefulWidget {
  const AdminProgramsScreen({super.key});

  @override
  State<AdminProgramsScreen> createState() => _AdminProgramsScreenState();
}

class _AdminProgramsScreenState extends State<AdminProgramsScreen> {
  String _query = '';
  String _status = 'all';

  static const _filters = ['all', 'open', 'full', ...['draft', 'closed', 'cancelled', 'completed', 'archived']];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final programs = state.programs.where((program) {
      final matchesQuery = '${program.title} ${program.location}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      final status = _status == 'full' ? program.displayStatus : program.status;
      return matchesQuery && (_status == 'all' || status == _status);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search programs',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemCount: _filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final statuses = _filters;
              final status = statuses[index];
              final selected = _status == status;
              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                selectedColor: AppTheme.ink,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: selected ? AppTheme.ink : AppTheme.border,
                ),
                label: Text(
                  status == 'all' ? 'All' : StatusPill.statusLabel(status),
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.inkSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _status = status),
              );
            },
          ),
        ),
        Expanded(
          child: !state.programsLoaded
              ? const Center(child: CircularProgressIndicator())
              : programs.isEmpty
              ? const EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No programs found',
                  message: 'Create a program or change the current filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                  itemCount: programs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    return ProgramCard(
                      program: program,
                      showArtwork: false,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProgramDetailAdmin(program: program),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

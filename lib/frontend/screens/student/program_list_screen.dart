import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/student_state.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'program_detail_screen.dart';

class ProgramListScreen extends StatefulWidget {
  const ProgramListScreen({super.key});

  @override
  State<ProgramListScreen> createState() => _ProgramListScreenState();
}

class _ProgramListScreenState extends State<ProgramListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';

  static const categories = [
    'All',
    'Academic',
    'Sports',
    'Leadership',
    'Career',
    'Volunteer',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StudentState>();
    final programs = state.openPrograms.where((program) {
      final searchable =
          '${program.title} ${program.description} ${program.location}'
              .toLowerCase();
      return searchable.contains(_query.toLowerCase()) &&
          (_category == 'All' || program.category == _category);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search by title or location',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = category == _category;
              return ChoiceChip(
                label: Text(category),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppTheme.ink,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: selected ? AppTheme.ink : AppTheme.border,
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _category = category),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: programs.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching programs',
                  message:
                      'Try another keyword or choose a different category.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: programs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    return ProgramCard(
                      program: program,
                      seatsKnown: state.seatsFor(program.id) != null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProgramDetailScreen(program: program),
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

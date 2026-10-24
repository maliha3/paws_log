import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/category_palette.dart';
import '../../core/widgets/empty_section.dart';
import '../../data/providers.dart';
import '../../domain/dose_schedule.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/pet_condition.dart';
import '../../domain/models/vaccination_record.dart';
import '../../domain/models/prescription.dart';
import '../health/visit_edit_screen.dart';
import 'condition_edit_screen.dart';
import 'prescription_detail_screen.dart';
import 'vaccination_edit_screen.dart';
import 'prescription_flow.dart';
import '../medicines/course_screen.dart';
import '../medicines/medicine_edit_screen.dart';

/// One pet's medical record, in four segments.
///
/// Segments rather than one long page: the four kinds of record are read at
/// different times — a prescription when a dose is in doubt, vaccines when a
/// cattery asks — and stacking them meant scrolling past three to reach the
/// fourth.
enum MedicalSegment {
  prescriptions('Prescriptions', Icons.receipt_long_outlined),
  medicines('Medicines', Icons.medication_outlined),
  vaccines('Vaccines', Icons.vaccines_outlined),
  visits('Vet visits', Icons.local_hospital_outlined),
  health('Health', Icons.monitor_heart_outlined);

  const MedicalSegment(this.label, this.icon);

  final String label;
  final IconData icon;
}

class MedicalScreen extends ConsumerStatefulWidget {
  const MedicalScreen({
    required this.petId,
    this.initialSegment = MedicalSegment.prescriptions,
    super.key,
  });

  final String petId;
  final MedicalSegment initialSegment;

  @override
  ConsumerState<MedicalScreen> createState() => _MedicalScreenState();
}

class _MedicalScreenState extends ConsumerState<MedicalScreen> {
  late MedicalSegment _segment = widget.initialSegment;

  @override
  Widget build(BuildContext context) {
    final pets = ref.watch(petsProvider);
    final pet = pets.hasValue
        ? pets.requireValue.where((pet) => pet.id == widget.petId).firstOrNull
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(pet == null ? 'Medical record' : '${pet.name}’s record'),
      ),
      floatingActionButton: _addButton(),
      body: Column(
        children: [
          _SegmentBar(
            selected: _segment,
            onChanged: (segment) => setState(() => _segment = segment),
          ),
          Expanded(
            child: switch (_segment) {
              MedicalSegment.prescriptions => _Prescriptions(petId: widget.petId),
              MedicalSegment.medicines => _Medicines(petId: widget.petId),
              MedicalSegment.vaccines => _Vaccines(petId: widget.petId),
              MedicalSegment.visits => _Visits(petId: widget.petId),
              MedicalSegment.health => _Health(petId: widget.petId),
            },
          ),
        ],
      ),
    );
  }

  /// Vaccines keep their automatic path — marking a vaccine reminder done
  /// writes one — but the button is there for the rest: a shot given at a
  /// clinic the app knew nothing about, and one from before the owner
  /// started using it.
  Widget? _addButton() => switch (_segment) {
    MedicalSegment.vaccines => FloatingActionButton(
      tooltip: 'Record a vaccination',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VaccinationEditScreen(petId: widget.petId),
        ),
      ),
      child: const Icon(Icons.add),
    ),
    MedicalSegment.prescriptions => FloatingActionButton(
      tooltip: 'Add a prescription',
      onPressed: () =>
          showAddPrescriptionSheet(context, ref, petId: widget.petId),
      child: const Icon(Icons.add),
    ),
    MedicalSegment.medicines => FloatingActionButton(
      tooltip: 'Add a medicine',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MedicineEditScreen(petId: widget.petId),
        ),
      ),
      child: const Icon(Icons.add),
    ),
    MedicalSegment.visits => FloatingActionButton(
      tooltip: 'Add a vet visit',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VisitEditScreen(petId: widget.petId),
        ),
      ),
      child: const Icon(Icons.add),
    ),
    MedicalSegment.health => FloatingActionButton(
      tooltip: 'Add to the health record',
      onPressed: _addHealthRecord,
      child: const Icon(Icons.add),
    ),
  };

  /// Two kinds of record behind one button, so the sheet asks which.
  Future<void> _addHealthRecord() => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Add a condition'),
              subtitle: const Text('Something your vet has diagnosed'),
              onTap: () {
                Navigator.of(sheet).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        ConditionEditScreen(petId: widget.petId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Add an allergy'),
              subtitle: const Text('Something they react to'),
              onTap: () {
                Navigator.of(sheet).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        AllergyEditScreen(petId: widget.petId),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// The four chips. Scrolls sideways rather than squeezing, so the labels
/// survive the largest text sizes.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.selected, required this.onChanged});

  final MedicalSegment selected;
  final ValueChanged<MedicalSegment> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      children: [
        for (final segment in MedicalSegment.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(segment.icon, size: 18),
              label: Text(segment.label),
              selected: segment == selected,
              showCheckmark: false,
              onSelected: (_) => onChanged(segment),
            ),
          ),
      ],
    ),
  );
}

/// Shared padding: room at the bottom for the add button to sit over.
const EdgeInsets _listPadding = EdgeInsets.fromLTRB(16, 8, 16, 96);

/// What a segment shows while its stream is still opening, or has failed.
class _SegmentBody<T> extends StatelessWidget {
  const _SegmentBody({required this.value, required this.builder});

  final AsyncValue<List<T>> value;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Padding(
      padding: _listPadding,
      child: Text('Something went wrong.\n$error'),
    ),
    data: builder,
  );
}

class _Prescriptions extends ConsumerWidget {
  const _Prescriptions({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SegmentBody(
    value: ref.watch(prescriptionsForPetProvider(petId)),
    builder: (prescriptions) => ListView(
      padding: _listPadding,
      children: [
        if (prescriptions.isEmpty)
          const EmptySection(
            icon: Icons.receipt_long_outlined,
            message:
                'No prescriptions yet. Scanning one keeps the page itself, so '
                'a dose can always be checked against what the vet wrote.',
          )
        else
          for (final prescription in prescriptions)
            _PrescriptionTile(petId: petId, prescription: prescription),
      ],
    ),
  );
}

class _PrescriptionTile extends ConsumerWidget {
  const _PrescriptionTile({required this.petId, required this.prescription});

  final String petId;
  final Prescription prescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pages = prescription.pageCount;
    final details = [
      pages == 1 ? '1 page' : '$pages pages',
      if (prescription.vetName != null) prescription.vetName!,
      if (prescription.clinic != null) prescription.clinic!,
    ].join(' · ');

    // What this page put on the schedule, so a course and its source are
    // never more than a glance apart.
    final from = ref.watch(medicinesFromPrescriptionProvider(prescription.id));
    final courses = (from.hasValue ? from.requireValue : const <Medicine>[])
        .map((medicine) => medicine.name)
        .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(DateFormat.yMMMd().format(prescription.date)),
        isThreeLine: courses.isNotEmpty,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            if (courses.isNotEmpty)
              Text(
                courses,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => PrescriptionDetailScreen(
              petId: petId,
              prescriptionId: prescription.id,
            ),
          ),
        ),
      ),
    );
  }
}

class _Medicines extends ConsumerWidget {
  const _Medicines({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A course that has run out is past even though nobody stopped it, so
    // the split needs today's date and not just the active flag.
    final today = localDateOnly(DateTime.now());
    bool isCurrent(Medicine medicine) =>
        medicine.isActive &&
        !(medicine.schedule.endDate?.isBefore(today) ?? false);

    return _SegmentBody(
      value: ref.watch(medicinesForPetProvider(petId)),
      builder: (medicines) {
        final current = medicines.where(isCurrent).toList();
        final past = medicines.where((m) => !isCurrent(m)).toList();

        return ListView(
          padding: _listPadding,
          children: [
            if (medicines.isEmpty)
              const EmptySection(
                icon: Icons.medication_outlined,
                message:
                    'No medicines. Add one and its doses appear on Today, '
                    'ready to tick off.',
              ),
            if (current.isNotEmpty) ...[
              const _GroupHeading('Active'),
              for (final medicine in current)
                MedicineTile(petId: petId, medicine: medicine),
            ],
            if (past.isNotEmpty) ...[
              if (current.isNotEmpty) const SizedBox(height: 12),
              const _GroupHeading('Past'),
              for (final medicine in past)
                MedicineTile(petId: petId, medicine: medicine),
            ],
          ],
        );
      },
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// One course, with what it is and when it runs.
class MedicineTile extends ConsumerWidget {
  const MedicineTile({
    required this.petId,
    required this.medicine,
    super.key,
  });

  final String petId;
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final schedule = medicine.schedule;
    final times = schedule.timesOfDayMinutes
        .map(
          (minutes) => TimeOfDay(
            hour: minutes ~/ 60,
            minute: minutes % 60,
          ).format(context),
        )
        .join(', ');

    final run = schedule.isOpenEnded
        ? 'from ${DateFormat.yMMMd().format(schedule.startDate)}, ongoing'
        : '${DateFormat.yMMMd().format(schedule.startDate)} – '
              '${DateFormat.yMMMd().format(schedule.endDate!)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        title: Text(
          medicine.name,
          style: TextStyle(
            decoration: medicine.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          [
            if (medicine.dosage != null) medicine.dosage!,
            times,
            run,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                CourseScreen(petId: petId, medicine: medicine),
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Medicine options',
          onSelected: (action) async {
            final repository = ref.read(medicineRepositoryProvider);
            switch (action) {
              case 'edit':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        MedicineEditScreen(petId: petId, medicine: medicine),
                  ),
                );
              case 'toggle':
                await repository.setActive(
                  medicine.id,
                  isActive: !medicine.isActive,
                );
              case 'delete':
                await repository.delete(medicine.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(medicine.isActive ? 'Stop course' : 'Restart'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _Vaccines extends ConsumerWidget {
  const _Vaccines({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SegmentBody(
    value: ref.watch(vaccinationsForPetProvider(petId)),
    builder: (records) => ListView(
      padding: _listPadding,
      children: [
        if (records.isEmpty)
          const EmptySection(
            icon: Icons.vaccines_outlined,
            message:
                'No vaccinations yet. Marking a vaccine reminder done records '
                'it here; add one by hand for a shot given elsewhere.',
          )
        else
          for (final record in records)
            _VaccinationTile(petId: petId, record: record),
      ],
    ),
  );
}

class _Visits extends ConsumerWidget {
  const _Visits({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SegmentBody(
    value: ref.watch(visitsForPetProvider(petId)),
    builder: (visits) => ListView(
      padding: _listPadding,
      children: [
        if (visits.isEmpty)
          const EmptySection(
            icon: Icons.local_hospital_outlined,
            message:
                'No visits yet. Record what the vet said, with photos of '
                'anything worth keeping.',
          )
        else
          for (final visit in visits)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.local_hospital_outlined),
                title: Text(visit.reason),
                subtitle: Text(
                  [
                    DateFormat.yMMMd().format(visit.visitedOn),
                    if (visit.clinic != null) visit.clinic!,
                    if (visit.cost != null) Money.format(visit.cost!),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        VisitEditScreen(petId: petId, visit: visit),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

/// Diagnosed conditions and allergies: what the cat has now, what it had,
/// and what it reacts to.
class _Health extends ConsumerWidget {
  const _Health({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conditions = ref.watch(conditionsForPetProvider(petId));
    final allergies = ref.watch(allergiesForPetProvider(petId));

    if (!conditions.hasValue || !allergies.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final ongoing = conditions.requireValue.where((c) => c.isOngoing).toList();
    final past = conditions.requireValue.where((c) => !c.isOngoing).toList();
    final reactions = allergies.requireValue;

    return ListView(
      padding: _listPadding,
      children: [
        if (ongoing.isEmpty && past.isEmpty && reactions.isEmpty)
          const EmptySection(
            icon: Icons.monitor_heart_outlined,
            message:
                'Nothing recorded. Add what your vet has diagnosed, and '
                'anything your cat reacts to, so it is to hand when it '
                'matters.',
          ),
        if (ongoing.isNotEmpty) ...[
          const _GroupHeading('Ongoing'),
          for (final condition in ongoing)
            _ConditionTile(petId: petId, condition: condition),
          const SizedBox(height: 12),
        ],
        if (past.isNotEmpty) ...[
          const _GroupHeading('Past'),
          for (final condition in past)
            _ConditionTile(petId: petId, condition: condition),
          const SizedBox(height: 12),
        ],
        if (reactions.isNotEmpty) ...[
          const _GroupHeading('Allergies'),
          for (final allergy in reactions)
            _AllergyTile(petId: petId, allergy: allergy),
        ],
      ],
    );
  }
}

class _ConditionTile extends ConsumerWidget {
  const _ConditionTile({required this.petId, required this.condition});

  final String petId;
  final PetCondition condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = [
      if (condition.date != null)
        'Diagnosed ${DateFormat.yMMMd().format(condition.date!)}',
      if (condition.notes != null) condition.notes!,
    ].join(' \u00b7 ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(condition.name),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: PopupMenuButton<String>(
          tooltip: 'Condition options',
          onSelected: (action) async {
            final health = ref.read(petHealthRepositoryProvider);
            switch (action) {
              case 'edit':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ConditionEditScreen(
                      petId: petId,
                      condition: condition,
                    ),
                  ),
                );
              case 'toggle':
                await health.setConditionStatus(
                  condition.id,
                  condition.isOngoing
                      ? ConditionStatus.past
                      : ConditionStatus.ongoing,
                );
              case 'delete':
                await health.deleteCondition(condition.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                condition.isOngoing ? 'Move to past' : 'Mark as ongoing',
              ),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _AllergyTile extends ConsumerWidget {
  const _AllergyTile({required this.petId, required this.allergy});

  final String petId;
  final PetAllergy allergy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = [
      if (allergy.reaction != null) allergy.reaction!,
      if (allergy.notes != null) allergy.notes!,
    ].join(' \u00b7 ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_rounded,
          color: context.categories.fleaTick,
        ),
        title: Text(allergy.allergen),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: PopupMenuButton<String>(
          tooltip: 'Allergy options',
          onSelected: (action) async {
            final health = ref.read(petHealthRepositoryProvider);
            if (action == 'edit') {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      AllergyEditScreen(petId: petId, allergy: allergy),
                ),
              );
            } else {
              await health.deleteAllergy(allergy.id);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _VaccinationTile extends ConsumerWidget {
  const _VaccinationTile({required this.petId, required this.record});

  final String petId;
  final VaccinationRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.vaccines_outlined),
      title: Text(record.name),
      subtitle: Text(
        [
          'Given ${DateFormat.yMMMd().format(record.administeredOn)}',
          if (record.nextDueOn != null)
            'next ${DateFormat.yMMMd().format(record.nextDueOn!)}',
          if (record.notes != null) record.notes!,
        ].join(' · '),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Vaccination options',
        onSelected: (action) async {
          if (action == 'edit') {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    VaccinationEditScreen(petId: petId, record: record),
              ),
            );
          } else {
            await ref.read(vaccinationRepositoryProvider).delete(record.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ),
  );
}

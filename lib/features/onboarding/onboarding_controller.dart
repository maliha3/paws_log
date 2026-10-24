import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../services/notifications/notification_providers.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_draft.dart';
import '../../domain/starter_reminders.dart';

/// Set by integration tests via `--dart-define`.
///
/// An integration test drives the Flutter view directly and cannot answer a
/// system permission dialog; worse, iOS makes the app inactive while one is
/// up, so pumped frames stop arriving and the test simply stalls.
const bool suppressPermissionPrompt = bool.fromEnvironment(
  'PAWSLOG_SUPPRESS_PERMISSION_PROMPT',
);

/// Everything the owner has entered during onboarding.
///
/// Held in one place so stepping back through the flow does not lose input.
class OnboardingDraft {
  const OnboardingDraft({
    this.name = '',
    this.photoPath,
    this.birthday,
    this.breed = '',
    this.sex = PetSex.unknown,
    this.neutered,
    this.coatLength,
    this.reminders = const [],
    this.isSaving = false,
  });

  final String name;
  final String? photoPath;

  /// Date-only, held at UTC midnight.
  final DateTime? birthday;

  final String breed;
  final PetSex sex;
  final bool? neutered;

  /// Asked during onboarding because the starter grooming suggestions depend
  /// on it: a long-haired cat is brushed far more often.
  final CoatLength? coatLength;

  final List<ReminderDraft> reminders;
  final bool isSaving;

  /// The name is the only thing onboarding insists on.
  bool get canContinue => name.trim().isNotEmpty;

  int get keptReminderCount =>
      reminders.where((reminder) => reminder.enabled).length;

  OnboardingDraft copyWith({
    String? name,
    String? photoPath,
    bool clearPhoto = false,
    DateTime? birthday,
    String? breed,
    PetSex? sex,
    bool? neutered,
    bool clearNeutered = false,
    CoatLength? coatLength,
    bool clearCoatLength = false,
    List<ReminderDraft>? reminders,
    bool? isSaving,
  }) => OnboardingDraft(
    name: name ?? this.name,
    photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    birthday: birthday ?? this.birthday,
    breed: breed ?? this.breed,
    sex: sex ?? this.sex,
    neutered: clearNeutered ? null : (neutered ?? this.neutered),
    coatLength: clearCoatLength ? null : (coatLength ?? this.coatLength),
    reminders: reminders ?? this.reminders,
    isSaving: isSaving ?? this.isSaving,
  );
}

/// Drives the onboarding flow and saves it at the end.
class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() =>
      OnboardingDraft(reminders: starterReminderDrafts());

  void setName(String value) => state = state.copyWith(name: value);

  void setPhoto(String? path) => state = path == null
      ? state.copyWith(clearPhoto: true)
      : state.copyWith(photoPath: path);

  void setBirthday(DateTime? value) =>
      state = state.copyWith(birthday: value);

  void setBreed(String value) => state = state.copyWith(breed: value);

  void setSex(PetSex value) => state = state.copyWith(sex: value);

  void setNeutered(bool? value) => state = value == null
      ? state.copyWith(clearNeutered: true)
      : state.copyWith(neutered: value);

  void setCoatLength(CoatLength? value) {
    state = value == null
        ? state.copyWith(clearCoatLength: true)
        : state.copyWith(coatLength: value);
    _retuneBrushing();
  }

  /// Re-times the brushing suggestion for the coat just chosen.
  ///
  /// The coat is picked on the screen before the reminders, so in practice
  /// this runs before the owner has seen them. Only the brushing interval is
  /// touched, so anything they have already changed elsewhere survives.
  void _retuneBrushing() {
    final repeat = brushingRepeatFor(state.coatLength);
    state = state.copyWith(
      reminders: [
        for (final draft in state.reminders)
          if (draft.category == ReminderCategory.brushing)
            draft.copyWith(repeat: repeat)
          else
            draft,
      ],
    );
  }

  void toggleReminder(int index, {required bool enabled}) =>
      _replaceReminder(index, state.reminders[index].copyWith(enabled: enabled));

  void updateReminder(int index, ReminderDraft draft) =>
      _replaceReminder(index, draft);

  void addReminder(ReminderDraft draft) =>
      state = state.copyWith(reminders: [...state.reminders, draft]);

  void removeReminder(int index) => state = state.copyWith(
    reminders: [...state.reminders]..removeAt(index),
  );

  void _replaceReminder(int index, ReminderDraft draft) {
    final next = [...state.reminders];
    next[index] = draft;
    state = state.copyWith(reminders: next);
  }

  /// Saves the pet and the reminders the owner kept.
  ///
  /// The pet has to exist before its reminders can reference it, so this is
  /// two repository calls; the reminders go in as a single transaction.
  Future<void> finish() async {
    if (!state.canContinue || state.isSaving) {
      return;
    }
    state = state.copyWith(isSaving: true);
    try {
      final now = DateTime.now();
      final pet = await ref.read(petRepositoryProvider).create(
        name: state.name,
        photoPath: state.photoPath,
        birthday: state.birthday,
        breed: state.breed,
        sex: state.sex,
        neutered: state.neutered,
        coatLength: state.coatLength,
        now: now,
      );
      await ref.read(reminderRepositoryProvider).createFromDrafts(
        petId: pet.id,
        drafts: state.reminders,
        now: now,
      );

      // Ask only now, with a schedule on screen to explain what the
      // notifications would be for. Not awaited: declining is a valid answer
      // and must not hold up the move to Today.
      if (state.keptReminderCount > 0 && !suppressPermissionPrompt) {
        unawaited(
          requestNotificationPermission(ref.read(notificationPluginProvider)),
        );
      }
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );

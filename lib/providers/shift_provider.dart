import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/shift_service.dart';
import 'app_providers.dart';

class ShiftState {
  final Shift? activeShift;
  final ShiftSummary? summary;
  final bool isLoading;

  const ShiftState({
    this.activeShift,
    this.summary,
    this.isLoading = false,
  });

  bool get hasActiveShift => activeShift != null;

  ShiftState copyWith({
    Shift? activeShift,
    bool clearShift = false,
    ShiftSummary? summary,
    bool clearSummary = false,
    bool? isLoading,
  }) {
    return ShiftState(
      activeShift: clearShift ? null : (activeShift ?? this.activeShift),
      summary: clearSummary ? null : (summary ?? this.summary),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ShiftNotifier extends StateNotifier<ShiftState> {
  final ShiftService shiftService;

  ShiftNotifier(this.shiftService) : super(const ShiftState());

  Future<void> checkActiveShift(String registerId) async {
    state = state.copyWith(isLoading: true);
    final shift = await shiftService.getOpenShift(registerId);
    ShiftSummary? summary;
    if (shift != null) {
      summary = await shiftService.calculateShiftSummary(shift.id);
    }
    state = state.copyWith(
      activeShift: shift,
      clearShift: shift == null,
      summary: summary,
      clearSummary: summary == null,
      isLoading: false,
    );
  }

  Future<Shift> openShift({
    required String registerId,
    required String cashierId,
    required Money openingCash,
    String? note,
  }) async {
    state = state.copyWith(isLoading: true);
    final shift = await shiftService.openShift(
      registerId: registerId,
      cashierId: cashierId,
      openingCash: openingCash,
      note: note,
    );
    final summary = await shiftService.calculateShiftSummary(shift.id);
    state = state.copyWith(activeShift: shift, summary: summary, isLoading: false);
    return shift;
  }

  Future<void> recordCashMovement({
    required String userId,
    required String type,
    required Money amount,
    required String reason,
  }) async {
    if (state.activeShift == null) return;
    await shiftService.recordCashMovement(
      shiftId: state.activeShift!.id,
      userId: userId,
      type: type,
      amount: amount,
      reason: reason,
    );
    final updated = await shiftService.calculateShiftSummary(state.activeShift!.id);
    state = state.copyWith(summary: updated);
  }

  Future<ShiftSummary> closeShift({
    required String cashierId,
    required Money countedCash,
    String? note,
  }) async {
    if (state.activeShift == null) throw Exception('No active shift to close');
    state = state.copyWith(isLoading: true);
    final summary = await shiftService.closeShift(
      shiftId: state.activeShift!.id,
      cashierId: cashierId,
      countedCash: countedCash,
      note: note,
    );
    state = state.copyWith(clearShift: true, summary: summary, isLoading: false);
    return summary;
  }
}

final shiftNotifierProvider = StateNotifierProvider<ShiftNotifier, ShiftState>((ref) {
  return ShiftNotifier(ref.watch(shiftServiceProvider));
});

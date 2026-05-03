import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../providers/bms_provider.dart';
final selectedDeviceProvider =
StateProvider<BluetoothDevice?>((ref) => null);
class BmsDashboard extends ConsumerWidget {
  const BmsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);

    // ✅ NEW CONDITION (only change)
    if (device == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("BMS Dashboard"),
          backgroundColor: const Color(0xFFFF8C00),
        ),
        body: const Center(
          child: Text("No device connected.\nGo back and select a device."),
        ),
      );
    }

    final snapshotAsync = ref.watch(bmsSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("BMS Dashboard"),
        backgroundColor: const Color(0xFFFF8C00),
      ),
      body: snapshotAsync.when(
        data: (snapshot) {
          final soc = snapshot.mainFrame?.soc ?? 0.0;
          final current = snapshot.mainFrame?.currentAmps ?? 0.0;
          final voltages = snapshot.cellFrame?.voltages ?? [];

          final status = current > 0.1
              ? "Charging"
              : current < -0.1
              ? "Discharging"
              : "Idle";

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${soc.toStringAsFixed(1)}%",
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 18,
                    color: current > 0.1
                        ? Colors.green
                        : current < -0.1
                        ? Colors.red
                        : Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Current: ${current.toStringAsFixed(2)} A",
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Cells",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...voltages.asMap().entries.map((entry) => Text(
                  "Cell ${entry.key + 1}: ${entry.value.toStringAsFixed(3)} V",
                )),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }
}
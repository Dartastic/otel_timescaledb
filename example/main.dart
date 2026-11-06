// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_timescaledb/otel_timescaledb.dart';

/// Traces Timescaledb calls with OpenTelemetry.
///
/// `otel_timescaledb` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Timescaledb call in
/// [tracedTimescaledb]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'timescaledb-example');

  // Wraps a TimescaleDB query in a CLIENT span using db.system=postgresql with timescaledb.* extras for hypertable-specific signals.
  final timescaledbId = await tracedTimescaledb<String>(
    operation: 'create',
    statementSummary: 'active',
    hypertable: 'orders',
    hostedFlavor: 'api.example.com',
    invoke: () async {
      // Make the Timescaledb call here, then report what it returned.
      const id = 'timescaledb_8f3a2c';
      return const TimescaledbCallResult(
          value: id,
          result: TimescaledbResult(
              rowsAffected: 1,
              chunksScanned: 1,
              compressedChunksScanned: 1,
              continuousAggregateUsed: true,
              timeRangeSec: 1));
    },
  );
  OTelLog.info('tracedTimescaledb create returned $timescaledbId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutTimescaledbInstrumentationAsync.
  await runWithoutTimescaledbInstrumentationAsync(
    () => tracedTimescaledb<String>(
      operation: 'create',
      statementSummary: 'active',
      hypertable: 'orders',
      hostedFlavor: 'api.example.com',
      invoke: () async {
        const id = 'timescaledb_8f3a2c';
        return const TimescaledbCallResult(
            value: id,
            result: TimescaledbResult(
                rowsAffected: 1,
                chunksScanned: 1,
                compressedChunksScanned: 1,
                continuousAggregateUsed: true,
                timeRangeSec: 1));
      },
    ),
  );

  await OTel.shutdown();
}

// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_timescaledb/otel_timescaledb.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_timescaledb-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('aggregate query records chunks + continuous_aggregate_used', () async {
    await tracedTimescaledb<String>(
      operation: 'select',
      hypertable: 'metrics',
      hostedFlavor: 'timescale_cloud',
      statementSummary:
          'SELECT time_bucket(?, ts), avg(v) FROM metrics WHERE ts > now()-?',
      invoke: () async => const TimescaledbCallResult(
        value: 'ok',
        result: TimescaledbResult(
          chunksScanned: 30,
          compressedChunksScanned: 28,
          continuousAggregateUsed: true,
          timeRangeSec: 7 * 86400,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('timescaledb select metrics')!);
    expect(a['db.system'], 'postgresql');
    expect(a['timescaledb.enabled'], true);
    expect(a['timescaledb.hypertable'], 'metrics');
    expect(a['timescaledb.flavor'], 'timescale_cloud');
    expect(a['timescaledb.continuous_aggregate_used'], true);
    expect(a['timescaledb.chunks_scanned'], 30);
    expect(a['timescaledb.compressed_chunks_scanned'], 28);
  });

  test('suppression skips spans', () async {
    await runWithoutTimescaledbInstrumentationAsync(() async {
      await tracedTimescaledb<String>(
        operation: 'select',
        statementSummary: 'x',
        invoke: () async => const TimescaledbCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('timescaledb '), isEmpty);
  });
}

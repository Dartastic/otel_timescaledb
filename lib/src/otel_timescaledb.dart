// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_timescaledb_suppression.dart';

const _tracerName = 'dartastic_otel_libs_timescaledb';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class TimescaledbResult {
  const TimescaledbResult({
    this.rowsAffected,
    this.chunksScanned,
    this.compressedChunksScanned,
    this.continuousAggregateUsed,
    this.timeRangeSec,
  });
  final int? rowsAffected;

  /// TimescaleDB queries fan out to per-time-range chunks. High chunk
  /// counts indicate the query window is too wide or chunks too small.
  final int? chunksScanned;

  /// Subset of [chunksScanned] that were compressed (column store).
  /// Compressed reads are slower per row but cheaper per byte.
  final int? compressedChunksScanned;

  /// True if the planner used a continuous aggregate / materialized
  /// rollup instead of scanning raw data. Major perf signal.
  final bool? continuousAggregateUsed;
  final int? timeRangeSec;
}

class TimescaledbCallResult<T> {
  const TimescaledbCallResult({required this.value, this.result});
  final T value;
  final TimescaledbResult? result;
}

/// Wraps a TimescaleDB query in a CLIENT span using db.system=postgresql
/// with timescaledb.* extras for hypertable-specific signals. Hosted
/// users (Timescale Cloud) can override [hostedFlavor].
Future<T> tracedTimescaledb<T>({
  required String operation,
  required String statementSummary,
  required Future<TimescaledbCallResult<T>> Function() invoke,
  String? hypertable,
  String? hostedFlavor,
}) async {
  if (timescaledbInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': 'postgresql',
    'db.operation.name': operation,
    'db.statement': statementSummary,
    'timescaledb.enabled': true,
  };
  if (hypertable != null) {
    m['db.collection.name'] = hypertable;
    m['timescaledb.hypertable'] = hypertable;
  }
  if (hostedFlavor != null) m['timescaledb.flavor'] = hostedFlavor;

  final span = _tracer().startSpan(
    'timescaledb $operation${hypertable != null ? ' $hypertable' : ''}',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.rowsAffected != null) {
        extras.add(OTel.attributeInt(
          'db.response.rows_affected',
          r.result!.rowsAffected!,
        ));
      }
      if (r.result!.chunksScanned != null) {
        extras.add(OTel.attributeInt(
          'timescaledb.chunks_scanned',
          r.result!.chunksScanned!,
        ));
      }
      if (r.result!.compressedChunksScanned != null) {
        extras.add(OTel.attributeInt(
          'timescaledb.compressed_chunks_scanned',
          r.result!.compressedChunksScanned!,
        ));
      }
      if (r.result!.continuousAggregateUsed != null) {
        extras.add(OTel.attributeBool(
          'timescaledb.continuous_aggregate_used',
          r.result!.continuousAggregateUsed!,
        ));
      }
      if (r.result!.timeRangeSec != null) {
        extras.add(OTel.attributeInt(
          'timescaledb.time_range_sec',
          r.result!.timeRangeSec!,
        ));
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

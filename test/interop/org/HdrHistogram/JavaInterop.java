package org.HdrHistogram;

import java.nio.ByteBuffer;

public class JavaInterop {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            throw new IllegalArgumentException("mode required: encode or decode");
        }
        String mode = args[0];
        if ("encode".equals(mode)) {
            if (args.length < 4) {
                throw new IllegalArgumentException("encode requires lowest highest sigfigs [values...]");
            }
            long lowest = Long.parseLong(args[1]);
            long highest = Long.parseLong(args[2]);
            int sigfigs = Integer.parseInt(args[3]);
            Histogram histogram = new Histogram(lowest, highest, sigfigs);
            for (int i = 4; i < args.length; i++) {
                String arg = args[i];
                int colon = arg.indexOf(':');
                long value;
                long count = 1;
                if (colon >= 0) {
                    value = Long.parseLong(arg.substring(0, colon));
                    count = Long.parseLong(arg.substring(colon + 1));
                } else {
                    value = Long.parseLong(arg);
                }
                histogram.recordValueWithCount(value, count);
            }
            ByteBuffer buffer = ByteBuffer.allocate(histogram.getNeededByteBufferCapacity());
            int written = histogram.encodeIntoCompressedByteBuffer(buffer);
            buffer.flip();
            byte[] bytes = new byte[written];
            buffer.get(bytes, 0, written);
            String payload = Base64Helper.printBase64Binary(bytes);
            System.out.print(payload);
            return;
        }
        if ("decode".equals(mode)) {
            if (args.length < 2) {
                throw new IllegalArgumentException("decode requires base64 payload");
            }
            String payload = args[1];
            byte[] bytes = Base64Helper.parseBase64Binary(payload);
            Histogram histogram = Histogram.decodeFromCompressedByteBuffer(ByteBuffer.wrap(bytes), 0);
            long total = histogram.getTotalCount();
            long min = histogram.getMinValue();
            long max = histogram.getMaxValue();
            long p99 = histogram.getValueAtPercentile(99.0);
            System.out.printf("%d,%d,%d,%d", total, min, max, p99);
            return;
        }
        if ("log".equals(mode)) {
            if (args.length < 6) {
                throw new IllegalArgumentException("log requires lowest highest sigfigs start_msec end_msec [tag] [values...]");
            }
            long lowest = Long.parseLong(args[1]);
            long highest = Long.parseLong(args[2]);
            int sigfigs = Integer.parseInt(args[3]);
            long startMsec = Long.parseLong(args[4]);
            long endMsec = Long.parseLong(args[5]);
            int valuesStart = 6;
            String tag = null;
            if (args.length > valuesStart && args[valuesStart].startsWith("tag=")) {
                tag = args[valuesStart].substring(4);
                valuesStart += 1;
            }
            Histogram histogram = new Histogram(lowest, highest, sigfigs);
            for (int i = valuesStart; i < args.length; i++) {
                String arg = args[i];
                int colon = arg.indexOf(':');
                long value;
                long count = 1;
                if (colon >= 0) {
                    value = Long.parseLong(arg.substring(0, colon));
                    count = Long.parseLong(arg.substring(colon + 1));
                } else {
                    value = Long.parseLong(arg);
                }
                histogram.recordValueWithCount(value, count);
            }
            histogram.setStartTimeStamp(startMsec);
            histogram.setEndTimeStamp(endMsec);
            if (tag != null && !tag.isEmpty()) {
                histogram.setTag(tag);
            }
            HistogramLogWriter writer = new HistogramLogWriter(System.out);
            writer.outputLogFormatVersion();
            writer.outputLegend();
            writer.outputIntervalHistogram(histogram);
            return;
        }
        if ("corrected".equals(mode)) {
            if (args.length < 6) {
                throw new IllegalArgumentException("corrected requires lowest highest sigfigs expected_interval value [count]");
            }
            long lowest = Long.parseLong(args[1]);
            long highest = Long.parseLong(args[2]);
            int sigfigs = Integer.parseInt(args[3]);
            long expectedInterval = Long.parseLong(args[4]);
            long value = Long.parseLong(args[5]);
            long count = (args.length > 6) ? Long.parseLong(args[6]) : 1;
            Histogram histogram = new Histogram(lowest, highest, sigfigs);
            histogram.recordValueWithCount(value, count);
            Histogram corrected = histogram.copyCorrectedForCoordinatedOmission(expectedInterval);
            long total = corrected.getTotalCount();
            long p99 = corrected.getValueAtPercentile(99.0);
            System.out.printf("%d,%d", total, p99);
            return;
        }
        if ("features".equals(mode)) {
            Histogram source = new Histogram(1, 1_000_000, 3);
            source.recordValueWithCount(0, 2);
            source.recordValueWithCount(10, 3);
            source.recordValue(10_000);
            source.setStartTimeStamp(100);
            source.setEndTimeStamp(400);
            source.setTag("source");

            Histogram copied = source.copy();
            Histogram largerCopy = new Histogram(1, 2_000_000, 3);
            source.copyInto(largerCopy);
            Histogram corrected = source.copyCorrectedForCoordinatedOmission(1_000);

            Histogram remainder = source.copy();
            Histogram removed = new Histogram(1, 1_000_000, 3);
            removed.recordValue(0);
            removed.recordValueWithCount(10, 2);
            remainder.subtract(removed);

            System.out.printf(
                    "%b,%b,%d,%d,%b,%d,%d,%d,%d,%.17g,%d,%d,%d,%d",
                    copied.equals(source), largerCopy.equals(source),
                    copied.getStartTimeStamp(), copied.getEndTimeStamp(), copied.getTag() == null,
                    corrected.getTotalCount(), corrected.getValueAtPercentile(99.0),
                    source.getMinNonZeroValue(), source.getCountBetweenValues(0, 10),
                    source.getPercentileAtOrBelowValue(10), remainder.getTotalCount(),
                    remainder.getCountAtValue(0), remainder.getCountAtValue(10),
                    remainder.getCountAtValue(10_000));
            return;
        }
        throw new IllegalArgumentException("unknown mode: " + mode);
    }
}

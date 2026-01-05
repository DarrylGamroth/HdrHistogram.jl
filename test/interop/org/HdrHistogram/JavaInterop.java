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
        throw new IllegalArgumentException("unknown mode: " + mode);
    }
}

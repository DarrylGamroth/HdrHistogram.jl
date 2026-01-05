import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import org.HdrHistogram.Histogram;

public final class CompareHdr {
    private static List<Long> readValues() throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        List<Long> values = new ArrayList<>();
        String line;
        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) {
                continue;
            }
            values.add(Long.parseLong(line));
        }
        return values;
    }

    private static void printStats(Histogram h) {
        System.out.println("total_count=" + h.getTotalCount());
        System.out.println("min=" + h.getMinValue());
        System.out.println("max=" + h.getMaxValue());
        System.out.println("mean=" + h.getMean());
        System.out.println("stddev=" + h.getStdDeviation());
        System.out.println("p50=" + h.getValueAtPercentile(50.0));
        System.out.println("p90=" + h.getValueAtPercentile(90.0));
        System.out.println("p99=" + h.getValueAtPercentile(99.0));
        System.out.println("p999=" + h.getValueAtPercentile(99.9));
        System.out.println("p100=" + h.getValueAtPercentile(100.0));
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("usage: CompareHdr <lowest> <highest> <sigfigs>");
            System.exit(2);
        }
        long lowest = Long.parseLong(args[0]);
        long highest = Long.parseLong(args[1]);
        int sigfigs = Integer.parseInt(args[2]);

        Histogram h = new Histogram(lowest, highest, sigfigs);
        for (long v : readValues()) {
            h.recordValue(v);
        }
        printStats(h);
    }
}

import ch.qos.logback.classic.LoggerContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import xyz.nulldev.ts.config.LoggingKt;

/** Runs against the packaged JAR, including its preserved logging dependencies. */
public class LoggingProbe {
    public static void main(String[] args) {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        context.reset();
        LoggingKt.initLoggerConfig(args[0], 3, "1mb", "3mb");
        boolean present = context.getLogger(Logger.ROOT_LOGGER_NAME)
            .getAppender("SuwayomiDefaultAppender") != null;
        LoggingKt.updateFileAppender(2, "1mb", "2mb");
        System.out.println("FILE_APPENDER=" + present);
        context.stop();
    }
}

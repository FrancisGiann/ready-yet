import dev.giann.before_i_leave.ScheduleTimePolicy;
import dev.giann.before_i_leave.ScheduleActionPolicy;
import java.util.Calendar;
import java.util.TimeZone;
import java.util.Locale;

public final class ScheduleTimePolicyCheck {
    static int assertions;
    static void expect(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
        System.out.println("PASS " + message);
    }
    public static void main(String[] args) {
        TimeZone utc = TimeZone.getTimeZone("UTC");
        long departure = ScheduleTimePolicy.departureAt(2026,10,19,420,utc);
        long reminder = ScheduleTimePolicy.reminderAt(departure,15);
        expect(departure-reminder==900000L,"15 minute lead is elapsed time before departure");
        expect(!ScheduleTimePolicy.mayRemind(reminder-1,reminder,departure,true,6,0),"never delivers early");
        expect(ScheduleTimePolicy.mayRemind(reminder,reminder,departure,true,6,2),"due incomplete occurrence may remind");
        expect(ScheduleTimePolicy.mayRemind(departure,departure,departure,true,6,0),"zero lead can remind at departure");
        expect(!ScheduleTimePolicy.mayRemind(departure+1,reminder,departure,true,6,0),"missed departure never causes late backlog");
        expect(!ScheduleTimePolicy.mayRemind(reminder,reminder,departure,false,6,0),"completed and skipped suppress reminders");
        expect(!ScheduleTimePolicy.mayRemind(reminder,reminder,departure,true,6,6),"fully packed checklist does not nag");
        expect(!ScheduleTimePolicy.mayRemind(reminder,reminder,departure,true,0,0),"empty checklist does not notify");
        expect(ScheduleTimePolicy.snoozeUntil(reminder,departure)==reminder+300000L,"snooze is five elapsed minutes");
        expect(ScheduleTimePolicy.snoozeUntil(departure-60000L,departure)==0L,"no snooze offered beyond departure");
        long midnight=ScheduleTimePolicy.departureAt(2026,10,19,5,utc);
        Calendar prior=Calendar.getInstance(utc); prior.setTimeInMillis(ScheduleTimePolicy.reminderAt(midnight,15));
        expect(prior.get(Calendar.DAY_OF_MONTH)==18 && prior.get(Calendar.HOUR_OF_DAY)==23 && prior.get(Calendar.MINUTE)==50,"cross-midnight lead retains next day's occurrence");
        Calendar monday=Calendar.getInstance(utc);monday.setTimeInMillis(midnight);
        expect(ScheduleTimePolicy.isoWeekday(monday)==1,"weekday convention Monday is one");
        expect(ScheduleTimePolicy.isoWeekday(prior)==7,"weekday convention Sunday is seven");
        TimeZone ny=TimeZone.getTimeZone("America/New_York");
        long spring=ScheduleTimePolicy.departureAt(2026,3,8,150,ny);
        expect(spring==ScheduleTimePolicy.departureAt(2026,3,8,450,utc),"spring gap 02:30 normalizes to 03:30 local");
        long autumn=ScheduleTimePolicy.departureAt(2026,11,1,90,ny);
        expect(autumn==ScheduleTimePolicy.departureAt(2026,11,1,390,utc),"autumn repeated hour uses one deterministic standard-time occurrence");
        expect(autumn==ScheduleTimePolicy.departureAt(2026,11,1,90,ny),"repeated recalculation never picks a second DST occurrence");
        long manila=ScheduleTimePolicy.departureAt(2026,10,19,420,TimeZone.getTimeZone("Asia/Manila"));
        expect(manila==ScheduleTimePolicy.departureAt(2026,10,18,1380,utc),"timezone change recalculates local departure");
        try { ScheduleTimePolicy.reminderAt(departure,-1); throw new AssertionError("negative lead accepted"); }
        catch (IllegalArgumentException expected) { assertions++; }
        expect(ScheduleTimePolicy.deliveryDeadline(departure,0)==departure+120000L,"at-departure delivery has two-minute latency grace");
        expect(ScheduleTimePolicy.deliveryDeadline(departure,15)==departure,"advance reminders expire at departure");
        expect(ScheduleActionPolicy.mayHandle("epoch","epoch","current","current","",true),"current incomplete notification action accepted");
        expect(!ScheduleActionPolicy.mayHandle("old","epoch","current","current","",true),"old reset epoch rejected");
        expect(!ScheduleActionPolicy.mayHandle("epoch","epoch","old","current","",true),"old notification token cannot affect newer reminder");
        expect(!ScheduleActionPolicy.mayHandle("epoch","epoch","current","current","current",true),"repeated action cannot extend snooze twice");
        expect(!ScheduleActionPolicy.mayHandle("epoch","epoch","current","current","",false),"finished skipped or packed occurrence rejects action");
        expect(!ScheduleActionPolicy.mayHandle("epoch","epoch","","","",true),"empty action token rejected");
        Locale originalLocale = Locale.getDefault();
        try {
            Locale.setDefault(new Locale("th", "TH"));
            expect(ScheduleTimePolicy.departureAt(2026,10,19,420,utc)==departure,"non-Gregorian device locale cannot change occurrence year");
        } finally { Locale.setDefault(originalLocale); }
        System.out.println("Schedule policies: " + assertions + " assertions passed");
    }
}

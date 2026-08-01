package work.shuyo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale

class ScheduleWidgetSmallProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget_small,
    rowBindings = emptyList(),
    compact = true
)

class ScheduleWidgetProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget,
    rowBindings = listOf(
        CourseRowBinding(R.id.course_row_1, R.id.course_time_1, R.id.course_name_1, R.id.course_meta_1),
        CourseRowBinding(R.id.course_row_2, R.id.course_time_2, R.id.course_name_2, R.id.course_meta_2),
        CourseRowBinding(R.id.course_row_3, R.id.course_time_3, R.id.course_name_3, R.id.course_meta_3)
    ),
    compact = false
)

class ScheduleWidgetLargeProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget_large,
    rowBindings = listOf(
        CourseRowBinding(R.id.course_row_1, R.id.course_time_1, R.id.course_name_1, R.id.course_meta_1),
        CourseRowBinding(R.id.course_row_2, R.id.course_time_2, R.id.course_name_2, R.id.course_meta_2),
        CourseRowBinding(R.id.course_row_3, R.id.course_time_3, R.id.course_name_3, R.id.course_meta_3),
        CourseRowBinding(R.id.course_row_4, R.id.course_time_4, R.id.course_name_4, R.id.course_meta_4),
        CourseRowBinding(R.id.course_row_5, R.id.course_time_5, R.id.course_name_5, R.id.course_meta_5)
    ),
    compact = false
)

abstract class ScheduleWidgetBaseProvider(
    private val layoutId: Int,
    private val rowBindings: List<CourseRowBinding>,
    private val compact: Boolean
) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val schedule = WidgetSchedule.parse(widgetData.getString(KEY_SNAPSHOT, null))
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, schedule)
            )
        }
    }

    private fun buildViews(context: Context, schedule: WidgetSchedule?): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId)
        views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context))

        if (schedule == null) {
            bindEmpty(views)
            return views
        }

        val now = LocalDateTime.now()
        val today = now.toLocalDate()
        val activeWeek = schedule.activeWeek(today)
        val todayCourses = schedule.courses
            .filter { course ->
                course.weekday == today.dayOfWeek.value &&
                    course.occursInWeek(activeWeek)
            }
            .sortedWith(compareBy<WidgetCourse> { it.startMinute }.thenBy { it.name })
        val nowMinute = now.hour * 60 + now.minute
        val upcoming = todayCourses.firstOrNull { it.endMinute >= nowMinute }

        if (compact) {
            bindCompact(views, activeWeek, today.dayOfWeek.value, todayCourses, upcoming, nowMinute)
            return views
        }

        val visibleCourses = todayCourses
            .filter { it.endMinute >= nowMinute }
            .ifEmpty { todayCourses.takeLast(rowBindings.size) }
            .take(rowBindings.size)

        views.setTextViewText(
            R.id.widget_title,
            schedule.term.ifBlank { "ShuYo课表" }
        )
        views.setTextViewText(
            R.id.widget_meta,
            "第${activeWeek}周 · ${weekdayName(today.dayOfWeek.value)}"
        )
        views.setTextViewText(
            R.id.widget_status,
            statusText(todayCourses, upcoming, nowMinute)
        )
        rowBindings.forEachIndexed { index, binding ->
            bindCourseRow(views, binding, visibleCourses.getOrNull(index), nowMinute)
        }
        return views
    }

    private fun bindEmpty(views: RemoteViews) {
        views.setTextViewText(R.id.widget_title, "ShuYo课表")
        views.setTextViewText(R.id.widget_meta, "")
        views.setTextViewText(R.id.widget_status, "打开 ShuYo 同步课表")
        if (compact) {
            views.setTextViewText(R.id.compact_course_meta, "本地还没有可显示的课程缓存")
        }
        rowBindings.forEach { binding ->
            bindCourseRow(views, binding, null, 0)
        }
    }

    private fun bindCompact(
        views: RemoteViews,
        activeWeek: Int,
        weekday: Int,
        todayCourses: List<WidgetCourse>,
        upcoming: WidgetCourse?,
        nowMinute: Int
    ) {
        views.setTextViewText(R.id.widget_title, "课表")
        views.setTextViewText(R.id.widget_meta, "第${activeWeek}周 · ${weekdayName(weekday)}")
        if (todayCourses.isEmpty()) {
            views.setTextViewText(R.id.widget_status, "今日暂无课程")
            views.setTextViewText(R.id.compact_course_meta, "点按打开 ShuYo")
            return
        }
        if (upcoming == null) {
            views.setTextViewText(R.id.widget_status, "今日课程已结束")
            views.setTextViewText(R.id.compact_course_meta, "点按打开 ShuYo")
            return
        }
        val prefix = if (upcoming.isActive(nowMinute)) "正在上课" else "下一节 ${upcoming.startText}"
        views.setTextViewText(R.id.widget_status, upcoming.name)
        views.setTextViewText(
            R.id.compact_course_meta,
            "$prefix · ${upcoming.meta.ifBlank { upcoming.sectionText }}"
        )
    }

    private fun bindCourseRow(
        views: RemoteViews,
        binding: CourseRowBinding,
        course: WidgetCourse?,
        nowMinute: Int
    ) {
        if (course == null) {
            views.setViewVisibility(binding.rowId, View.GONE)
            return
        }
        views.setViewVisibility(binding.rowId, View.VISIBLE)
        views.setInt(
            binding.rowId,
            "setBackgroundResource",
            if (course.isActive(nowMinute)) {
                R.drawable.widget_course_row_active_background
            } else {
                R.drawable.widget_course_row_background
            }
        )
        views.setTextViewText(binding.timeId, "${course.startText}-${course.endText}")
        views.setTextViewText(binding.nameId, course.name)
        views.setTextViewText(
            binding.metaId,
            course.meta.ifBlank { course.sectionText }
        )
    }

    private fun statusText(
        todayCourses: List<WidgetCourse>,
        upcoming: WidgetCourse?,
        nowMinute: Int
    ): String {
        if (todayCourses.isEmpty()) {
            return "今日暂无课程"
        }
        if (upcoming == null) {
            return "今日课程已结束"
        }
        if (upcoming.isActive(nowMinute)) {
            return "正在上课 · ${upcoming.name}"
        }
        return "下一节 ${upcoming.startText} · ${upcoming.name}"
    }

    private fun launchIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openSchedule", true)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(context, 9201, intent, flags)
    }

    private fun weekdayName(weekday: Int): String {
        return when (weekday) {
            1 -> "周一"
            2 -> "周二"
            3 -> "周三"
            4 -> "周四"
            5 -> "周五"
            6 -> "周六"
            7 -> "周日"
            else -> ""
        }
    }

    companion object {
        private const val KEY_SNAPSHOT = "academic_schedule_widget_snapshot"
    }
}

data class CourseRowBinding(
    val rowId: Int,
    val timeId: Int,
    val nameId: Int,
    val metaId: Int
)

private data class WidgetSchedule(
    val term: String,
    val maxWeek: Int,
    val currentWeek: Int,
    val anchorMonday: String,
    val courses: List<WidgetCourse>
) {
    fun activeWeek(today: LocalDate): Int {
        val anchor = parseDate(anchorMonday) ?: return currentWeek.coerceIn(1, maxWeek)
        val todayMonday = today.minusDays((today.dayOfWeek.value - 1).toLong())
        val weekOffset = ChronoUnit.WEEKS.between(anchor, todayMonday).toInt()
        return (currentWeek + weekOffset).coerceIn(1, maxWeek.coerceAtLeast(1))
    }

    companion object {
        fun parse(raw: String?): WidgetSchedule? {
            if (raw.isNullOrBlank()) {
                return null
            }
            return try {
                val json = JSONObject(raw)
                if (!json.optBoolean("hasSchedule", false)) {
                    return null
                }
                val sessions = mutableListOf<WidgetCourse>()
                val sessionJson = json.optJSONArray("sessions")
                if (sessionJson != null) {
                    for (index in 0 until sessionJson.length()) {
                        val course = WidgetCourse.parse(
                            sessionJson.optJSONObject(index) ?: continue
                        )
                        if (course != null) {
                            sessions.add(course)
                        }
                    }
                }
                WidgetSchedule(
                    term = json.optString("term", ""),
                    maxWeek = json.optInt("maxWeek", 1).coerceAtLeast(1),
                    currentWeek = json.optInt("currentWeek", 1).coerceAtLeast(1),
                    anchorMonday = json.optString("anchorMonday", ""),
                    courses = sessions
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}

private data class WidgetCourse(
    val name: String,
    val meta: String,
    val weekday: Int,
    val weeks: Set<Int>,
    val startMinute: Int,
    val endMinute: Int,
    val startText: String,
    val endText: String,
    val sectionText: String
) {
    fun occursInWeek(week: Int): Boolean = weeks.isEmpty() || weeks.contains(week)

    fun isActive(minute: Int): Boolean = minute in startMinute..endMinute

    companion object {
        fun parse(json: JSONObject): WidgetCourse? {
            val name = json.optString("name", "").trim()
            val weekday = json.optInt("weekday", 0)
            val startMinute = json.optInt("startMinute", -1)
            val endMinute = json.optInt("endMinute", -1)
            if (name.isBlank() ||
                weekday !in 1..7 ||
                startMinute < 0 ||
                endMinute < startMinute
            ) {
                return null
            }

            val weeks = mutableSetOf<Int>()
            val weekJson = json.optJSONArray("weeks")
            if (weekJson != null) {
                for (index in 0 until weekJson.length()) {
                    val week = weekJson.optInt(index, 0)
                    if (week > 0) {
                        weeks.add(week)
                    }
                }
            }

            return WidgetCourse(
                name = name,
                meta = json.optString("meta", "").trim(),
                weekday = weekday,
                weeks = weeks,
                startMinute = startMinute,
                endMinute = endMinute,
                startText = json.optString("startText", formatMinute(startMinute)),
                endText = json.optString("endText", formatMinute(endMinute)),
                sectionText = json.optString("sectionText", "").trim()
            )
        }

        private fun formatMinute(minute: Int): String {
            return String.format(
                Locale.US,
                "%02d:%02d",
                minute / 60,
                minute % 60
            )
        }
    }
}

private fun parseDate(value: String): LocalDate? {
    val datePart = value.substringBefore("T").ifBlank { return null }
    return try {
        LocalDate.parse(datePart)
    } catch (_: Exception) {
        null
    }
}

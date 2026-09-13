// // Copyright 2024 The Flutter Workmanager Authors. All rights reserved.
// // Use of this source code is governed by a MIT-style license that can be
// // found in the LICENSE file.
// файл создаёт pigeon версии 26.3.4, ручные изменения при генерации пропадут
@file:Suppress("UNCHECKED_CAST", "ArrayInDataClass")

package dev.fluttercommunity.workmanager.pigeon

import android.util.Log
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.common.StandardMessageCodec
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
private object WorkmanagerApiPigeonUtils {

  fun createConnectionError(channelName: String): FlutterError {
    return FlutterError("channel-error",  "Unable to establish connection on channel: '$channelName'.", "")  }

  fun wrapResult(result: Any?): List<Any?> {
    return listOf(result)
  }

  fun wrapError(exception: Throwable): List<Any?> {
    return if (exception is FlutterError) {
      listOf(
        exception.code,
        exception.message,
        exception.details
      )
    } else {
      listOf(
        exception.javaClass.simpleName,
        exception.toString(),
        "Cause: " + exception.cause + ", Stacktrace: " + Log.getStackTraceString(exception)
      )
    }
  }
  fun doubleEquals(a: Double, b: Double): Boolean {
    // нормализуем отрицательный ноль и учитываем равенство NaN
    return (if (a == 0.0) 0.0 else a) == (if (b == 0.0) 0.0 else b) || (a.isNaN() && b.isNaN())
  }

  fun floatEquals(a: Float, b: Float): Boolean {
    return (if (a == 0.0f) 0.0f else a) == (if (b == 0.0f) 0.0f else b) || (a.isNaN() && b.isNaN())
  }

  fun doubleHash(d: Double): Int {
    // нормализуем отрицательный ноль и NaN, чтобы хеши оставались согласованными
    val normalized = if (d == 0.0) 0.0 else d
    val bits = java.lang.Double.doubleToLongBits(normalized)
    return (bits xor (bits ushr 32)).toInt()
  }

  fun floatHash(f: Float): Int {
    val normalized = if (f == 0.0f) 0.0f else f
    return java.lang.Float.floatToIntBits(normalized)
  }

  fun deepEquals(a: Any?, b: Any?): Boolean {
    if (a === b) {
      return true
    }
    if (a == null || b == null) {
      return false
    }
    if (a is ByteArray && b is ByteArray) {
      return a.contentEquals(b)
    }
    if (a is IntArray && b is IntArray) {
      return a.contentEquals(b)
    }
    if (a is LongArray && b is LongArray) {
      return a.contentEquals(b)
    }
    if (a is DoubleArray && b is DoubleArray) {
      if (a.size != b.size) return false
      for (i in a.indices) {
        if (!doubleEquals(a[i], b[i])) return false
      }
      return true
    }
    if (a is FloatArray && b is FloatArray) {
      if (a.size != b.size) return false
      for (i in a.indices) {
        if (!floatEquals(a[i], b[i])) return false
      }
      return true
    }
    if (a is Array<*> && b is Array<*>) {
      if (a.size != b.size) return false
      for (i in a.indices) {
        if (!deepEquals(a[i], b[i])) return false
      }
      return true
    }
    if (a is List<*> && b is List<*>) {
      if (a.size != b.size) return false
      val iterA = a.iterator()
      val iterB = b.iterator()
      while (iterA.hasNext() && iterB.hasNext()) {
        if (!deepEquals(iterA.next(), iterB.next())) return false
      }
      return true
    }
    if (a is Map<*, *> && b is Map<*, *>) {
      if (a.size != b.size) return false
      for (entry in a) {
        val key = entry.key
        var found = false
        for (bEntry in b) {
          if (deepEquals(key, bEntry.key)) {
            if (deepEquals(entry.value, bEntry.value)) {
              found = true
              break
            } else {
              return false
            }
          }
        }
        if (!found) return false
      }
      return true
    }
    if (a is Double && b is Double) {
      return doubleEquals(a, b)
    }
    if (a is Float && b is Float) {
      return floatEquals(a, b)
    }
    return a == b
  }

  fun deepHash(value: Any?): Int {
    return when (value) {
      null -> 0
      is ByteArray -> value.contentHashCode()
      is IntArray -> value.contentHashCode()
      is LongArray -> value.contentHashCode()
      is DoubleArray -> {
        var result = 1
        for (item in value) {
          result = 31 * result + doubleHash(item)
        }
        result
      }
      is FloatArray -> {
        var result = 1
        for (item in value) {
          result = 31 * result + floatHash(item)
        }
        result
      }
      is Array<*> -> {
        var result = 1
        for (item in value) {
          result = 31 * result + deepHash(item)
        }
        result
      }
      is List<*> -> {
        var result = 1
        for (item in value) {
          result = 31 * result + deepHash(item)
        }
        result
      }
      is Map<*, *> -> {
        var result = 0
        for (entry in value) {
          result += ((deepHash(entry.key) * 31) xor deepHash(entry.value))
        }
        result
      }
      is Double -> doubleHash(value)
      is Float -> floatHash(value)
      else -> value.hashCode()
    }
  }

}

/** детали ошибки должны поддерживаться кодеком для передачи во flutter */
class FlutterError (
  val code: String,
  override val message: String? = null,
  val details: Any? = null
) : RuntimeException()

/** состояние задачи нужно для отладки и наблюдения */
enum class TaskStatus(val raw: Int) {
  SCHEDULED(0),
  STARTED(1),
  COMPLETED(2),
  FAILED(3),
  CANCELLED(4),
  RETRYING(5),
  RESCHEDULED(6);

  companion object {
    fun ofRaw(raw: Int): TaskStatus? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** на android доступны все ограничения сети, на ios учитываются только connected и metered */
enum class NetworkType(val raw: Int) {
  CONNECTED(0),
  METERED(1),
  NOT_REQUIRED(2),
  NOT_ROAMING(3),
  UNMETERED(4),
  /** временно бесплатная сеть поддерживается начиная с android api 30 */
  TEMPORARILY_UNMETERED(5);

  companion object {
    fun ofRaw(raw: Int): NetworkType? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** политика задаёт рост задержки после запроса повторной попытки воркером */
enum class BackoffPolicy(val raw: Int) {
  EXPONENTIAL(0),
  LINEAR(1);

  companion object {
    fun ofRaw(raw: Int): BackoffPolicy? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** политика решает конфликт разовых задач с одним уникальным именем */
enum class ExistingWorkPolicy(val raw: Int) {
  /** новую задачу добавляем после всех конечных задач незавершённой цепочки с тем же именем */
  APPEND(0),
  /** при незавершённой задаче с тем же именем новый запрос игнорируется */
  KEEP(1),
  /** прежнюю незавершённую задачу с тем же именем отменяем и заменяем */
  REPLACE(2),
  /** нативная реализация использует appendOrReplace */
  UPDATE(3);

  companion object {
    fun ofRaw(raw: Int): ExistingWorkPolicy? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** политика решает конфликт периодических задач с одним именем, в том числе при смене частоты */
enum class ExistingPeriodicWorkPolicy(val raw: Int) {
  /** повторная регистрация сохраняет прежнюю частоту, для её изменения нужен update */
  KEEP(0),
  /** замена отменяет прежнюю задачу, update позволяет обойтись без отмены */
  REPLACE(1),
  /** обновление сохраняет время и работающий воркер, доступно с workmanager 2.8.0 */
  UPDATE(2);

  companion object {
    fun ofRaw(raw: Int): ExistingPeriodicWorkPolicy? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** поведение при исчерпании квоты срочных задач настраивается только на android */
enum class OutOfQuotaPolicy(val raw: Int) {
  /** без квоты срочную задачу выполняем как обычную */
  RUN_AS_NON_EXPEDITED_WORK_REQUEST(0),
  /** без квоты срочную задачу не ставим в очередь */
  DROP_WORK_REQUEST(1);

  companion object {
    fun ofRaw(raw: Int): OutOfQuotaPolicy? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** на apple состояние хранит плагин, потому что у BGTaskScheduler нет api для чтения задач */
enum class WorkState(val raw: Int) {
  SCHEDULED(0),
  RUNNING(1),
  SUCCEEDED(2),
  FAILED(3),
  CANCELLED(4);

  companion object {
    fun ofRaw(raw: Int): WorkState? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** с android 14 для долгой foreground службы нужно явно указать тип */
enum class ForegroundServiceType(val raw: Int) {
  /** тип службы для долгой синхронизации, загрузки и отправки данных */
  DATA_SYNC(0),
  /** тип службы для короткой важной работы продолжительностью не более нескольких минут */
  SHORT_SERVICE(1);

  companion object {
    fun ofRaw(raw: Int): ForegroundServiceType? {
      return values().firstOrNull { it.raw == raw }
    }
  }
}

/** на android служба с уведомлением удерживает процесс во время долгой задачи, отсутствующие настройки заполняет платформа */
data class ForegroundServiceConfig (
  val notificationTitle: String? = null,
  val notificationText: String? = null,
  /** канал уведомления используется начиная с android 8 */
  val notificationChannelId: String? = null,
  val notificationChannelName: String? = null,
  val notificationId: Long? = null,
  /** с android 14 по умолчанию используется тип dataSync */
  val foregroundServiceType: ForegroundServiceType? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): ForegroundServiceConfig {
      val notificationTitle = pigeonVar_list[0] as String?
      val notificationText = pigeonVar_list[1] as String?
      val notificationChannelId = pigeonVar_list[2] as String?
      val notificationChannelName = pigeonVar_list[3] as String?
      val notificationId = pigeonVar_list[4] as Long?
      val foregroundServiceType = pigeonVar_list[5] as ForegroundServiceType?
      return ForegroundServiceConfig(notificationTitle, notificationText, notificationChannelId, notificationChannelName, notificationId, foregroundServiceType)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      notificationTitle,
      notificationText,
      notificationChannelId,
      notificationChannelName,
      notificationId,
      foregroundServiceType,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as ForegroundServiceConfig
    return WorkmanagerApiPigeonUtils.deepEquals(this.notificationTitle, other.notificationTitle) && WorkmanagerApiPigeonUtils.deepEquals(this.notificationText, other.notificationText) && WorkmanagerApiPigeonUtils.deepEquals(this.notificationChannelId, other.notificationChannelId) && WorkmanagerApiPigeonUtils.deepEquals(this.notificationChannelName, other.notificationChannelName) && WorkmanagerApiPigeonUtils.deepEquals(this.notificationId, other.notificationId) && WorkmanagerApiPigeonUtils.deepEquals(this.foregroundServiceType, other.foregroundServiceType)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.notificationTitle)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.notificationText)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.notificationChannelId)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.notificationChannelName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.notificationId)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.foregroundServiceType)
    return result
  }
}

data class Constraints (
  val networkType: NetworkType? = null,
  val requiresBatteryNotLow: Boolean? = null,
  val requiresCharging: Boolean? = null,
  val requiresDeviceIdle: Boolean? = null,
  val requiresStorageNotLow: Boolean? = null,
  /** триггеры content uri доступны с android 7, число одновременно поставленных задач по умолчанию ограничено восемью */
  val contentUriTriggers: List<ContentUriTrigger?>? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): Constraints {
      val networkType = pigeonVar_list[0] as NetworkType?
      val requiresBatteryNotLow = pigeonVar_list[1] as Boolean?
      val requiresCharging = pigeonVar_list[2] as Boolean?
      val requiresDeviceIdle = pigeonVar_list[3] as Boolean?
      val requiresStorageNotLow = pigeonVar_list[4] as Boolean?
      val contentUriTriggers = pigeonVar_list[5] as List<ContentUriTrigger?>?
      return Constraints(networkType, requiresBatteryNotLow, requiresCharging, requiresDeviceIdle, requiresStorageNotLow, contentUriTriggers)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      networkType,
      requiresBatteryNotLow,
      requiresCharging,
      requiresDeviceIdle,
      requiresStorageNotLow,
      contentUriTriggers,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as Constraints
    return WorkmanagerApiPigeonUtils.deepEquals(this.networkType, other.networkType) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresBatteryNotLow, other.requiresBatteryNotLow) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresCharging, other.requiresCharging) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresDeviceIdle, other.requiresDeviceIdle) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresStorageNotLow, other.requiresStorageNotLow) && WorkmanagerApiPigeonUtils.deepEquals(this.contentUriTriggers, other.contentUriTriggers)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.networkType)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresBatteryNotLow)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresCharging)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresDeviceIdle)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresStorageNotLow)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.contentUriTriggers)
    return result
  }
}

/** изменение, вставка или удаление по content uri запускает связанную задачу */
data class ContentUriTrigger (
  /** наблюдаем локальный адрес со схемой content */
  val uri: String,
  /** флаг включает наблюдение за дочерними адресами */
  val triggerForDescendants: Boolean
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): ContentUriTrigger {
      val uri = pigeonVar_list[0] as String
      val triggerForDescendants = pigeonVar_list[1] as Boolean
      return ContentUriTrigger(uri, triggerForDescendants)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uri,
      triggerForDescendants,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as ContentUriTrigger
    return WorkmanagerApiPigeonUtils.deepEquals(this.uri, other.uri) && WorkmanagerApiPigeonUtils.deepEquals(this.triggerForDescendants, other.triggerForDescendants)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uri)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.triggerForDescendants)
    return result
  }
}

data class BackoffPolicyConfig (
  val backoffPolicy: BackoffPolicy? = null,
  val backoffDelayMillis: Long? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): BackoffPolicyConfig {
      val backoffPolicy = pigeonVar_list[0] as BackoffPolicy?
      val backoffDelayMillis = pigeonVar_list[1] as Long?
      return BackoffPolicyConfig(backoffPolicy, backoffDelayMillis)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      backoffPolicy,
      backoffDelayMillis,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as BackoffPolicyConfig
    return WorkmanagerApiPigeonUtils.deepEquals(this.backoffPolicy, other.backoffPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.backoffDelayMillis, other.backoffDelayMillis)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.backoffPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.backoffDelayMillis)
    return result
  }
}

data class InitializeRequest (
  val callbackHandle: Long
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): InitializeRequest {
      val callbackHandle = pigeonVar_list[0] as Long
      return InitializeRequest(callbackHandle)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      callbackHandle,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as InitializeRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.callbackHandle, other.callbackHandle)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.callbackHandle)
    return result
  }
}

data class OneOffTaskRequest (
  val uniqueName: String,
  val taskName: String,
  val inputData: Map<String?, Any?>? = null,
  val initialDelaySeconds: Long? = null,
  val constraints: Constraints? = null,
  val backoffPolicy: BackoffPolicyConfig? = null,
  val tag: String? = null,
  val existingWorkPolicy: ExistingWorkPolicy? = null,
  val outOfQuotaPolicy: OutOfQuotaPolicy? = null,
  val foregroundServiceConfig: ForegroundServiceConfig? = null,
  /** ускорение доступно только разовым задачам android, периодические задачи его не поддерживают */
  val expedited: Boolean? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): OneOffTaskRequest {
      val uniqueName = pigeonVar_list[0] as String
      val taskName = pigeonVar_list[1] as String
      val inputData = pigeonVar_list[2] as Map<String?, Any?>?
      val initialDelaySeconds = pigeonVar_list[3] as Long?
      val constraints = pigeonVar_list[4] as Constraints?
      val backoffPolicy = pigeonVar_list[5] as BackoffPolicyConfig?
      val tag = pigeonVar_list[6] as String?
      val existingWorkPolicy = pigeonVar_list[7] as ExistingWorkPolicy?
      val outOfQuotaPolicy = pigeonVar_list[8] as OutOfQuotaPolicy?
      val foregroundServiceConfig = pigeonVar_list[9] as ForegroundServiceConfig?
      val expedited = pigeonVar_list[10] as Boolean?
      return OneOffTaskRequest(uniqueName, taskName, inputData, initialDelaySeconds, constraints, backoffPolicy, tag, existingWorkPolicy, outOfQuotaPolicy, foregroundServiceConfig, expedited)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      taskName,
      inputData,
      initialDelaySeconds,
      constraints,
      backoffPolicy,
      tag,
      existingWorkPolicy,
      outOfQuotaPolicy,
      foregroundServiceConfig,
      expedited,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as OneOffTaskRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.inputData, other.inputData) && WorkmanagerApiPigeonUtils.deepEquals(this.initialDelaySeconds, other.initialDelaySeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.constraints, other.constraints) && WorkmanagerApiPigeonUtils.deepEquals(this.backoffPolicy, other.backoffPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.tag, other.tag) && WorkmanagerApiPigeonUtils.deepEquals(this.existingWorkPolicy, other.existingWorkPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.outOfQuotaPolicy, other.outOfQuotaPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.foregroundServiceConfig, other.foregroundServiceConfig) && WorkmanagerApiPigeonUtils.deepEquals(this.expedited, other.expedited)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.inputData)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.initialDelaySeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.constraints)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.backoffPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.tag)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.existingWorkPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.outOfQuotaPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.foregroundServiceConfig)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.expedited)
    return result
  }
}

data class PeriodicTaskRequest (
  val uniqueName: String,
  val taskName: String,
  val frequencySeconds: Long,
  val flexIntervalSeconds: Long? = null,
  val inputData: Map<String?, Any?>? = null,
  val initialDelaySeconds: Long? = null,
  val constraints: Constraints? = null,
  val backoffPolicy: BackoffPolicyConfig? = null,
  val tag: String? = null,
  val existingWorkPolicy: ExistingPeriodicWorkPolicy? = null,
  val foregroundServiceConfig: ForegroundServiceConfig? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): PeriodicTaskRequest {
      val uniqueName = pigeonVar_list[0] as String
      val taskName = pigeonVar_list[1] as String
      val frequencySeconds = pigeonVar_list[2] as Long
      val flexIntervalSeconds = pigeonVar_list[3] as Long?
      val inputData = pigeonVar_list[4] as Map<String?, Any?>?
      val initialDelaySeconds = pigeonVar_list[5] as Long?
      val constraints = pigeonVar_list[6] as Constraints?
      val backoffPolicy = pigeonVar_list[7] as BackoffPolicyConfig?
      val tag = pigeonVar_list[8] as String?
      val existingWorkPolicy = pigeonVar_list[9] as ExistingPeriodicWorkPolicy?
      val foregroundServiceConfig = pigeonVar_list[10] as ForegroundServiceConfig?
      return PeriodicTaskRequest(uniqueName, taskName, frequencySeconds, flexIntervalSeconds, inputData, initialDelaySeconds, constraints, backoffPolicy, tag, existingWorkPolicy, foregroundServiceConfig)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      taskName,
      frequencySeconds,
      flexIntervalSeconds,
      inputData,
      initialDelaySeconds,
      constraints,
      backoffPolicy,
      tag,
      existingWorkPolicy,
      foregroundServiceConfig,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as PeriodicTaskRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.frequencySeconds, other.frequencySeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.flexIntervalSeconds, other.flexIntervalSeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.inputData, other.inputData) && WorkmanagerApiPigeonUtils.deepEquals(this.initialDelaySeconds, other.initialDelaySeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.constraints, other.constraints) && WorkmanagerApiPigeonUtils.deepEquals(this.backoffPolicy, other.backoffPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.tag, other.tag) && WorkmanagerApiPigeonUtils.deepEquals(this.existingWorkPolicy, other.existingWorkPolicy) && WorkmanagerApiPigeonUtils.deepEquals(this.foregroundServiceConfig, other.foregroundServiceConfig)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.frequencySeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.flexIntervalSeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.inputData)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.initialDelaySeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.constraints)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.backoffPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.tag)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.existingWorkPolicy)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.foregroundServiceConfig)
    return result
  }
}

data class ProcessingTaskRequest (
  val uniqueName: String,
  val taskName: String,
  val inputData: Map<String?, Any?>? = null,
  val initialDelaySeconds: Long? = null,
  val networkType: NetworkType? = null,
  val requiresCharging: Boolean? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): ProcessingTaskRequest {
      val uniqueName = pigeonVar_list[0] as String
      val taskName = pigeonVar_list[1] as String
      val inputData = pigeonVar_list[2] as Map<String?, Any?>?
      val initialDelaySeconds = pigeonVar_list[3] as Long?
      val networkType = pigeonVar_list[4] as NetworkType?
      val requiresCharging = pigeonVar_list[5] as Boolean?
      return ProcessingTaskRequest(uniqueName, taskName, inputData, initialDelaySeconds, networkType, requiresCharging)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      taskName,
      inputData,
      initialDelaySeconds,
      networkType,
      requiresCharging,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as ProcessingTaskRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.inputData, other.inputData) && WorkmanagerApiPigeonUtils.deepEquals(this.initialDelaySeconds, other.initialDelaySeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.networkType, other.networkType) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresCharging, other.requiresCharging)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.inputData)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.initialDelaySeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.networkType)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresCharging)
    return result
  }
}

data class HealthResearchTaskRequest (
  val uniqueName: String,
  val taskName: String,
  val inputData: Map<String?, Any?>? = null,
  val initialDelaySeconds: Long? = null,
  val networkType: NetworkType? = null,
  val requiresCharging: Boolean? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): HealthResearchTaskRequest {
      val uniqueName = pigeonVar_list[0] as String
      val taskName = pigeonVar_list[1] as String
      val inputData = pigeonVar_list[2] as Map<String?, Any?>?
      val initialDelaySeconds = pigeonVar_list[3] as Long?
      val networkType = pigeonVar_list[4] as NetworkType?
      val requiresCharging = pigeonVar_list[5] as Boolean?
      return HealthResearchTaskRequest(uniqueName, taskName, inputData, initialDelaySeconds, networkType, requiresCharging)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      taskName,
      inputData,
      initialDelaySeconds,
      networkType,
      requiresCharging,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as HealthResearchTaskRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.inputData, other.inputData) && WorkmanagerApiPigeonUtils.deepEquals(this.initialDelaySeconds, other.initialDelaySeconds) && WorkmanagerApiPigeonUtils.deepEquals(this.networkType, other.networkType) && WorkmanagerApiPigeonUtils.deepEquals(this.requiresCharging, other.requiresCharging)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.inputData)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.initialDelaySeconds)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.networkType)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.requiresCharging)
    return result
  }
}

data class ContinuedProcessingTaskRequest (
  val uniqueName: String,
  val taskName: String,
  val title: String? = null,
  val subtitle: String? = null,
  val inputData: Map<String?, Any?>? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): ContinuedProcessingTaskRequest {
      val uniqueName = pigeonVar_list[0] as String
      val taskName = pigeonVar_list[1] as String
      val title = pigeonVar_list[2] as String?
      val subtitle = pigeonVar_list[3] as String?
      val inputData = pigeonVar_list[4] as Map<String?, Any?>?
      return ContinuedProcessingTaskRequest(uniqueName, taskName, title, subtitle, inputData)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      taskName,
      title,
      subtitle,
      inputData,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as ContinuedProcessingTaskRequest
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.title, other.title) && WorkmanagerApiPigeonUtils.deepEquals(this.subtitle, other.subtitle) && WorkmanagerApiPigeonUtils.deepEquals(this.inputData, other.inputData)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.title)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.subtitle)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.inputData)
    return result
  }
}

/** снимок нативной задачи передаём в общий для платформ WorkInfo */
data class WorkInfoData (
  val uniqueName: String,
  val state: WorkState,
  val isPeriodic: Boolean,
  val taskName: String? = null,
  /** теги доступны только на android, на остальных платформах список пуст */
  val tags: List<String?>? = null,
  /** workmanager не сообщает время завершения, поэтому на android здесь null */
  val lastFinishedAtMillis: Long? = null
)
 {
  companion object {
    fun fromList(pigeonVar_list: List<Any?>): WorkInfoData {
      val uniqueName = pigeonVar_list[0] as String
      val state = pigeonVar_list[1] as WorkState
      val isPeriodic = pigeonVar_list[2] as Boolean
      val taskName = pigeonVar_list[3] as String?
      val tags = pigeonVar_list[4] as List<String?>?
      val lastFinishedAtMillis = pigeonVar_list[5] as Long?
      return WorkInfoData(uniqueName, state, isPeriodic, taskName, tags, lastFinishedAtMillis)
    }
  }
  fun toList(): List<Any?> {
    return listOf(
      uniqueName,
      state,
      isPeriodic,
      taskName,
      tags,
      lastFinishedAtMillis,
    )
  }
  override fun equals(other: Any?): Boolean {
    if (other == null || other.javaClass != javaClass) {
      return false
    }
    if (this === other) {
      return true
    }
    val other = other as WorkInfoData
    return WorkmanagerApiPigeonUtils.deepEquals(this.uniqueName, other.uniqueName) && WorkmanagerApiPigeonUtils.deepEquals(this.state, other.state) && WorkmanagerApiPigeonUtils.deepEquals(this.isPeriodic, other.isPeriodic) && WorkmanagerApiPigeonUtils.deepEquals(this.taskName, other.taskName) && WorkmanagerApiPigeonUtils.deepEquals(this.tags, other.tags) && WorkmanagerApiPigeonUtils.deepEquals(this.lastFinishedAtMillis, other.lastFinishedAtMillis)
  }

  override fun hashCode(): Int {
    var result = javaClass.hashCode()
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.uniqueName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.state)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.isPeriodic)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.taskName)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.tags)
    result = 31 * result + WorkmanagerApiPigeonUtils.deepHash(this.lastFinishedAtMillis)
    return result
  }
}
private open class WorkmanagerApiPigeonCodec : StandardMessageCodec() {
  override fun readValueOfType(type: Byte, buffer: ByteBuffer): Any? {
    return when (type) {
      129.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          TaskStatus.ofRaw(it.toInt())
        }
      }
      130.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          NetworkType.ofRaw(it.toInt())
        }
      }
      131.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          BackoffPolicy.ofRaw(it.toInt())
        }
      }
      132.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          ExistingWorkPolicy.ofRaw(it.toInt())
        }
      }
      133.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          ExistingPeriodicWorkPolicy.ofRaw(it.toInt())
        }
      }
      134.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          OutOfQuotaPolicy.ofRaw(it.toInt())
        }
      }
      135.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          WorkState.ofRaw(it.toInt())
        }
      }
      136.toByte() -> {
        return (readValue(buffer) as Long?)?.let {
          ForegroundServiceType.ofRaw(it.toInt())
        }
      }
      137.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          ForegroundServiceConfig.fromList(it)
        }
      }
      138.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          Constraints.fromList(it)
        }
      }
      139.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          ContentUriTrigger.fromList(it)
        }
      }
      140.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          BackoffPolicyConfig.fromList(it)
        }
      }
      141.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          InitializeRequest.fromList(it)
        }
      }
      142.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          OneOffTaskRequest.fromList(it)
        }
      }
      143.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          PeriodicTaskRequest.fromList(it)
        }
      }
      144.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          ProcessingTaskRequest.fromList(it)
        }
      }
      145.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          HealthResearchTaskRequest.fromList(it)
        }
      }
      146.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          ContinuedProcessingTaskRequest.fromList(it)
        }
      }
      147.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          WorkInfoData.fromList(it)
        }
      }
      else -> super.readValueOfType(type, buffer)
    }
  }
  override fun writeValue(stream: ByteArrayOutputStream, value: Any?)   {
    when (value) {
      is TaskStatus -> {
        stream.write(129)
        writeValue(stream, value.raw.toLong())
      }
      is NetworkType -> {
        stream.write(130)
        writeValue(stream, value.raw.toLong())
      }
      is BackoffPolicy -> {
        stream.write(131)
        writeValue(stream, value.raw.toLong())
      }
      is ExistingWorkPolicy -> {
        stream.write(132)
        writeValue(stream, value.raw.toLong())
      }
      is ExistingPeriodicWorkPolicy -> {
        stream.write(133)
        writeValue(stream, value.raw.toLong())
      }
      is OutOfQuotaPolicy -> {
        stream.write(134)
        writeValue(stream, value.raw.toLong())
      }
      is WorkState -> {
        stream.write(135)
        writeValue(stream, value.raw.toLong())
      }
      is ForegroundServiceType -> {
        stream.write(136)
        writeValue(stream, value.raw.toLong())
      }
      is ForegroundServiceConfig -> {
        stream.write(137)
        writeValue(stream, value.toList())
      }
      is Constraints -> {
        stream.write(138)
        writeValue(stream, value.toList())
      }
      is ContentUriTrigger -> {
        stream.write(139)
        writeValue(stream, value.toList())
      }
      is BackoffPolicyConfig -> {
        stream.write(140)
        writeValue(stream, value.toList())
      }
      is InitializeRequest -> {
        stream.write(141)
        writeValue(stream, value.toList())
      }
      is OneOffTaskRequest -> {
        stream.write(142)
        writeValue(stream, value.toList())
      }
      is PeriodicTaskRequest -> {
        stream.write(143)
        writeValue(stream, value.toList())
      }
      is ProcessingTaskRequest -> {
        stream.write(144)
        writeValue(stream, value.toList())
      }
      is HealthResearchTaskRequest -> {
        stream.write(145)
        writeValue(stream, value.toList())
      }
      is ContinuedProcessingTaskRequest -> {
        stream.write(146)
        writeValue(stream, value.toList())
      }
      is WorkInfoData -> {
        stream.write(147)
        writeValue(stream, value.toList())
      }
      else -> super.writeValue(stream, value)
    }
  }
}


interface WorkmanagerHostApi {
  fun initialize(request: InitializeRequest, callback: (Result<Unit>) -> Unit)
  fun registerOneOffTask(request: OneOffTaskRequest, callback: (Result<Unit>) -> Unit)
  fun registerPeriodicTask(request: PeriodicTaskRequest, callback: (Result<Unit>) -> Unit)
  fun registerProcessingTask(request: ProcessingTaskRequest, callback: (Result<Unit>) -> Unit)
  fun registerHealthResearchTask(request: HealthResearchTaskRequest, callback: (Result<Unit>) -> Unit)
  fun registerContinuedProcessingTask(request: ContinuedProcessingTaskRequest, callback: (Result<Unit>) -> Unit)
  fun cancelByUniqueName(uniqueName: String, callback: (Result<Unit>) -> Unit)
  fun cancelByTag(tag: String, callback: (Result<Unit>) -> Unit)
  fun cancelAll(callback: (Result<Unit>) -> Unit)
  fun isScheduledByUniqueName(uniqueName: String, callback: (Result<Boolean>) -> Unit)
  fun printScheduledTasks(callback: (Result<String>) -> Unit)
  /** если платформа не хранит задачу с этим именем, возвращаем null */
  fun getWorkInfoByUniqueName(uniqueName: String, callback: (Result<WorkInfoData?>) -> Unit)
  /** прогресс передаём из фонового обработчика android, на других платформах вызов ничего не делает */
  fun reportProgress(progress: Map<String?, Any?>?, callback: (Result<Unit>) -> Unit)
  /** на android прогресс поступает messenger движка, который зарегистрировал слушателя */
  fun setProgressListener(enabled: Boolean, callback: (Result<Unit>) -> Unit)
  /** нативный воркер ждёт регистрации обработчиков dart, иначе первая отправленная задача может потеряться */
  fun notifyBackgroundChannelInitialized(callback: (Result<Unit>) -> Unit)

  companion object {
    val codec: MessageCodec<Any?> by lazy {
      WorkmanagerApiPigeonCodec()
    }
    @JvmOverloads
    fun setUp(binaryMessenger: BinaryMessenger, api: WorkmanagerHostApi?, messageChannelSuffix: String = "") {
      val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.initialize$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as InitializeRequest
            api.initialize(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.registerOneOffTask$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as OneOffTaskRequest
            api.registerOneOffTask(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.registerPeriodicTask$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as PeriodicTaskRequest
            api.registerPeriodicTask(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.registerProcessingTask$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as ProcessingTaskRequest
            api.registerProcessingTask(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.registerHealthResearchTask$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as HealthResearchTaskRequest
            api.registerHealthResearchTask(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.registerContinuedProcessingTask$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val requestArg = args[0] as ContinuedProcessingTaskRequest
            api.registerContinuedProcessingTask(requestArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.cancelByUniqueName$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val uniqueNameArg = args[0] as String
            api.cancelByUniqueName(uniqueNameArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.cancelByTag$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val tagArg = args[0] as String
            api.cancelByTag(tagArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.cancelAll$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            api.cancelAll{ result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.isScheduledByUniqueName$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val uniqueNameArg = args[0] as String
            api.isScheduledByUniqueName(uniqueNameArg) { result: Result<Boolean> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.printScheduledTasks$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            api.printScheduledTasks{ result: Result<String> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.getWorkInfoByUniqueName$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val uniqueNameArg = args[0] as String
            api.getWorkInfoByUniqueName(uniqueNameArg) { result: Result<WorkInfoData?> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.reportProgress$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val progressArg = args[0] as Map<String?, Any?>?
            api.reportProgress(progressArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.setProgressListener$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val enabledArg = args[0] as Boolean
            api.setProgressListener(enabledArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.notifyBackgroundChannelInitialized$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            api.notifyBackgroundChannelInitialized{ result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(WorkmanagerApiPigeonUtils.wrapError(error))
              } else {
                reply.reply(WorkmanagerApiPigeonUtils.wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
    }
  }
}
class WorkmanagerFlutterApi(private val binaryMessenger: BinaryMessenger, private val messageChannelSuffix: String = "") {
  companion object {
    val codec: MessageCodec<Any?> by lazy {
      WorkmanagerApiPigeonCodec()
    }
  }
  fun backgroundChannelInitialized(callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.backgroundChannelInitialized$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(null) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(WorkmanagerApiPigeonUtils.createConnectionError(channelName)))
      } 
    }
  }
  fun executeTask(taskNameArg: String, inputDataArg: Map<String?, Any?>?, callback: (Result<Boolean>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.executeTask$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(taskNameArg, inputDataArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else if (it[0] == null) {
          callback(Result.failure(FlutterError("null-error", "Flutter api returned null value for non-null return value.", "")))
        } else {
          val output = it[0] as Boolean
          callback(Result.success(output))
        }
      } else {
        callback(Result.failure(WorkmanagerApiPigeonUtils.createConnectionError(channelName)))
      } 
    }
  }
  /** при досрочной остановке даём dart сохранить состояние; до android 12 причина неизвестна */
  fun onTaskStopped(taskNameArg: String, stopReasonArg: Long, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.onTaskStopped$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(taskNameArg, stopReasonArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(WorkmanagerApiPigeonUtils.createConnectionError(channelName)))
      } 
    }
  }
  /** прогресс android отправляем только при зарегистрированном слушателе приложения */
  fun onProgressUpdate(uniqueNameArg: String, progressArg: Map<String?, Any?>?, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.onProgressUpdate$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(uniqueNameArg, progressArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(WorkmanagerApiPigeonUtils.createConnectionError(channelName)))
      } 
    }
  }
}

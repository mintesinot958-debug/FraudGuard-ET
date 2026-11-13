package et.fraudguard.eth_fraud_guard

import android.Manifest
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "et.fraudguard/sms"
    private val permissionRequestCode = 4107
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestReadPermission" -> requestReadPermission(result)
                    "readRecentSms" -> readRecentSms(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestReadPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("permission_in_progress", "SMS permission request is already active.", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_SMS),
            permissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            permissionResult?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            permissionResult = null
        }
    }

    private fun readRecentSms(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission_denied", "SMS inbox permission has not been granted.", null)
            return
        }

        try {
            val messages = mutableListOf<Map<String, Any?>>()
            val cursor: Cursor? = contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                null,
                null,
                "${Telephony.Sms.DATE} DESC",
            )
            cursor?.use {
                val senderColumn = it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyColumn = it.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateColumn = it.getColumnIndexOrThrow(Telephony.Sms.DATE)
                while (it.moveToNext() && messages.size < 100) {
                    messages.add(
                        mapOf(
                            "sender" to it.getString(senderColumn),
                            "body" to it.getString(bodyColumn),
                            "date" to it.getLong(dateColumn),
                        ),
                    )
                }
            }
            result.success(messages)
        } catch (error: SecurityException) {
            result.error("permission_denied", "SMS inbox access was denied.", null)
        } catch (error: Exception) {
            result.error("sms_read_failed", "Could not read SMS inbox.", error.message)
        }
    }
}

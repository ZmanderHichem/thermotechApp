package com.example.saadoun

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.IBinder
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageReference
import com.google.firebase.firestore.FirebaseFirestore
import android.net.Uri
import android.provider.MediaStore
import android.database.Cursor
import android.widget.Toast
import java.io.File
import android.provider.ContactsContract
import android.os.PowerManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.google.firebase.auth.FirebaseAuth

class ForegroundService : Service() {
    private var phoneCallReceiver: PhoneCallReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val sharedPreferences by lazy {
        getSharedPreferences("FailedUploads", Context.MODE_PRIVATE)
    }

    override fun onCreate() {
        super.onCreate()

        // Create a notification channel for the foreground service
        createNotificationChannel()

        // Build and start the foreground notification
        val notification = NotificationCompat.Builder(this, "ForegroundServiceChannel")
            .setContentTitle("Listening for phone calls")
            .setContentText("Running in the background")
            .setSmallIcon(R.drawable.bell) // Set bell.png in assets folder as icon
            .setOngoing(true) // Make the notification non-dismissible
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(1, notification)

        // Register phone call receiver
        phoneCallReceiver = PhoneCallReceiver(sharedPreferences) { phoneNumber ->
            Log.d("ForegroundService", "Phone call ended: $phoneNumber")
        }
        registerReceiver(phoneCallReceiver, IntentFilter("android.intent.action.PHONE_STATE"))

        // Acquire a wake lock
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ForegroundService::WakeLock")
        wakeLock?.acquire()

        // Request to ignore battery optimizations
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = android.content.Intent()
            val packageName = packageName
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                intent.data = android.net.Uri.parse("package:$packageName")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        }

        // Register connectivity change receiver
        registerReceiver(connectivityReceiver, IntentFilter("android.net.conn.CONNECTIVITY_CHANGE"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        phoneCallReceiver?.let {
            unregisterReceiver(it)
        }
        // Release the wake lock
        wakeLock?.release()
        unregisterReceiver(connectivityReceiver)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                "ForegroundServiceChannel",
                "Foreground Service Channel",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    class PhoneCallReceiver(
        private val sharedPreferences: SharedPreferences,
        val onCallEnded: (String?) -> Unit
    ) : BroadcastReceiver() {
        private var phoneNumber: String? = null
        private var callStartTime: Long = 0
        private val uploadedFiles = mutableSetOf<Uri>() // Set to keep track of uploaded files

        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getStringExtra(TelephonyManager.EXTRA_STATE)

            when (state) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    phoneNumber = intent?.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                }

                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    phoneNumber = intent?.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                    callStartTime = System.currentTimeMillis() // Record the start time of the call
                }

                TelephonyManager.EXTRA_STATE_IDLE -> {
                    val callEndTime = System.currentTimeMillis()
                    val callDuration = callEndTime - callStartTime

                    if (callDuration > 0) { // Check if the call duration is more than 0 seconds
                        // Call ended, trigger the callback
                        onCallEnded(phoneNumber)
                        context?.let {
                            val contactName = getContactName(it, phoneNumber)
                            Handler(Looper.getMainLooper()).postDelayed({
                                val recentFileUri = getMostRecentFileUri(it, callDuration)
                                Log.d("ForegroundService", "Recent file URI: $recentFileUri")
                                recentFileUri?.let { uri ->
                                    if (!uploadedFiles.contains(uri)) { // Check if the file has already been uploaded
                                        uploadFileToFirebase(uri, it, phoneNumber , contactName)
                                        uploadedFiles.add(uri) // Add the file URI to the set after uploading
                                    } else {
                                        Log.d("ForegroundService", "File already uploaded: ${uri.lastPathSegment}")
                                    }
                                }
                            }, 2000)

                            Log.d(
                                "ForegroundService",
                                "Phone call ended: $phoneNumber, Contact Name: $contactName"
                            )
                        }
                    }
                }
            }
        }

        private fun getContactName(context: Context, phoneNumber: String?): String? {
            phoneNumber ?: return null
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(phoneNumber)
            )
            val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getString(cursor.getColumnIndexOrThrow(ContactsContract.PhoneLookup.DISPLAY_NAME))
                }
            }
            return null
        }

        private fun getMostRecentFileUri(context: Context, callDuration: Long): Uri? {
            val projection = arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DATE_ADDED)
            val sortOrder = "${MediaStore.Files.FileColumns.DATE_ADDED} DESC"
            val uri: Uri = MediaStore.Files.getContentUri("external")
            val currentTime = System.currentTimeMillis() / 1000
            val fourSecondsAgo = currentTime - (callDuration / 1000) - 10

            val selection = "${MediaStore.Files.FileColumns.DATE_ADDED} >= ?"
            val selectionArgs = arrayOf(fourSecondsAgo.toString())

            context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id =
                        cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID))
                    return Uri.withAppendedPath(uri, id.toString())
                }
            }
            return null
        }


        private fun uploadFileToFirebase(fileUri: Uri, context: Context, phoneNumber: String?, contactName: String?) {
            val user = FirebaseAuth.getInstance().currentUser
            if (user?.email == "yousef.zmander@gmail.com") {
                val storage = FirebaseStorage.getInstance()
                val storageRef = storage.reference
                val fileRef = storageRef.child("uploads/${fileUri.lastPathSegment}")

                fileRef.putFile(fileUri)
                    .addOnSuccessListener {
                        fileRef.downloadUrl.addOnSuccessListener { uri ->
                            val fileUrl = uri.toString()
                            createFirestoreDocument(fileUrl, phoneNumber, contactName, context)
                            createClientDocument(phoneNumber, contactName, fileUrl)
                            
                            // Show success notification
                            showUploadNotification(context, fileUri.lastPathSegment ?: "File", "Upload Successful", "File uploaded successfully")
                        }
                        Log.d(
                            "PhoneCallReceiver",
                            "File uploaded successfully: ${fileUri.lastPathSegment}"
                        )
                    }
                    .addOnFailureListener { exception ->
                        Log.e("PhoneCallReceiver", "File upload failed", exception)
                        // Save failed upload to SharedPreferences
                        sharedPreferences.edit().putString(fileUri.toString(), fileUri.toString()).apply()
                        
                        // Show failure notification
                        showUploadNotification(context, fileUri.lastPathSegment ?: "File", "Upload Failed", "File upload failed")
                    }
                    .addOnProgressListener { taskSnapshot ->
                        val progress = (100.0 * taskSnapshot.bytesTransferred / taskSnapshot.totalByteCount)
                        Log.d("PhoneCallReceiver", "Upload is $progress% done")
                        
                        // Show progress notification
                    }
            } else {
                Log.d("PhoneCallReceiver", "Upload skipped: User email is not authorized")
            }
        }

        private fun showUploadNotification(context: Context, fileName: String, title: String, content: String) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Create notification channel if necessary
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    "UploadNotificationChannel",
                    "Upload Notifications",
                    NotificationManager.IMPORTANCE_HIGH
                )
                notificationManager.createNotificationChannel(channel)
            }

            // Build the notification
            val notification = NotificationCompat.Builder(context, "UploadNotificationChannel")
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(R.drawable.bell) // Ensure you have an appropriate icon
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()

            // Show the notification
            notificationManager.notify(fileName.hashCode(), notification)
        }

        private fun createFirestoreDocument(
            fileUrl: String,
            phoneNumber: String?,
            contactName: String?,
            context: Context
        ) {
            val db = FirebaseFirestore.getInstance()
            val currentTime = System.currentTimeMillis()
            val recordData = hashMapOf(
                "url" to fileUrl,
                "timestamp" to currentTime
            )

            phoneNumber?.let {
                val docRef = db.collection("rdv_suggerer").document(it)
                docRef.get()
                    .addOnSuccessListener { document ->
                        if (document.exists()) {
                            // Document exists, add to subcollection
                            docRef.collection("records")
                                .add(recordData)
                                .addOnSuccessListener {
                                    Log.d("PhoneCallReceiver", "Record added to subcollection")
                                }
                                .addOnFailureListener { exception ->
                                    Log.e(
                                        "PhoneCallReceiver",
                                        "Failed to add record to subcollection",
                                        exception
                                    )
                                }
                        } else {
                            // Document does not exist, create it with the phone number as ID
                            docRef.set(hashMapOf("tel" to phoneNumber, "contactName" to contactName))
                                .addOnSuccessListener {
                                    // Add the record to the subcollection
                                    docRef.collection("records")
                                        .add(recordData)
                                        .addOnSuccessListener {
                                            Log.d(
                                                "PhoneCallReceiver",
                                                "Record added to subcollection"
                                            )
                                        }
                                        .addOnFailureListener { exception ->
                                            Log.e(
                                                "PhoneCallReceiver",
                                                "Failed to add record to subcollection",
                                                exception
                                            )
                                        }
                                }
                                .addOnFailureListener { exception ->
                                    Log.e(
                                        "PhoneCallReceiver",
                                        "Failed to create document",
                                        exception
                                    )
                                }
                        }
                    }
                    .addOnFailureListener { exception ->
                        Log.e("PhoneCallReceiver", "Failed to get document", exception)
                    }
            }
        }

        private fun createClientDocument(phoneNumber: String?, contactName: String?, fileUrl: String) {
           
            val db = FirebaseFirestore.getInstance()
            val currentTime = System.currentTimeMillis()
            val recordData = hashMapOf(
                "url" to fileUrl,
                "timestamp" to currentTime
            )
            phoneNumber?.let {
                val docRef = db.collection("clients").document(it)
                docRef.get()
                    .addOnSuccessListener { document ->
                        if (document.exists()) {
                            // Document exists, add to subcollection
                            docRef.collection("records")
                                .add(recordData)
                                .addOnSuccessListener {
                                    Log.d("PhoneCallReceiver", "Record added to subcollection")
                                }
                                .addOnFailureListener { exception ->
                                    Log.e(
                                        "PhoneCallReceiver",
                                        "Failed to add record to subcollection",
                                        exception
                                    )
                                }
                        } else {
                            // Document does not exist, create it with the phone number as ID
                            docRef.set(hashMapOf("numero_telephone" to phoneNumber, "nom_client" to contactName))
                                .addOnSuccessListener {
                                    // Add the record to the subcollection
                                    docRef.collection("records")
                                        .add(recordData)
                                        .addOnSuccessListener {
                                            Log.d(
                                                "PhoneCallReceiver",
                                                "Record added to subcollection"
                                            )
                                        }
                                        .addOnFailureListener { exception ->
                                            Log.e(
                                                "PhoneCallReceiver",
                                                "Failed to add record to subcollection",
                                                exception
                                            )
                                        }
                                }
                                .addOnFailureListener { exception ->
                                    Log.e(
                                        "PhoneCallReceiver",
                                        "Failed to create document",
                                        exception
                                    )
                                }
                        }
                    }
                    .addOnFailureListener { exception ->
                        Log.e("PhoneCallReceiver", "Failed to get document", exception)
                    }
            }
        }

        fun retryFailedUploads(context: Context) {
            val failedUploads = sharedPreferences.all
            for ((key, value) in failedUploads) {
                val fileUri = Uri.parse(value as String)
                // Retry the upload
                uploadFileToFirebase(fileUri, context, null, null)
                // Remove from SharedPreferences after successful upload
                sharedPreferences.edit().remove(key).apply()
            }
        }
    }

    private val connectivityReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (isConnectedToInternet(context)) {
                phoneCallReceiver?.retryFailedUploads(context!!)
            }
        }
    }

    private fun isConnectedToInternet(context: Context?): Boolean {
        // Implement a method to check internet connectivity
        // This can be done using ConnectivityManager
        return true // Placeholder
    }
}

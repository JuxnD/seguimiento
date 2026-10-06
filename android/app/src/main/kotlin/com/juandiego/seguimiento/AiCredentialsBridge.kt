package com.juandiego.seguimiento

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Solo guarda la licencia revocable. Nunca recibe la clave de OpenAI. */
class AiCredentialsBridge(private val context: Context) {
    private val alias = "seguimiento-license-v1"
    // noBackupFilesDir no participa en Android Auto Backup ni paquetes manuales.
    private val file get() = java.io.File(context.noBackupFilesDir, "ai-activation.json")
    private fun read(): org.json.JSONObject = if (file.exists())
        org.json.JSONObject(file.readText()) else org.json.JSONObject()
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias)) return store.getKey(alias, null) as SecretKey
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun save(data: org.json.JSONObject) {
        val tmp = java.io.File(file.parentFile, "ai-activation.tmp")
        java.io.FileOutputStream(tmp).use { stream -> stream.write(data.toString().toByteArray()); stream.fd.sync() }
        if (!tmp.renameTo(file)) throw java.io.IOException("Atomic rename failed")
    }
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            val data = read()
            if (!data.has("hwid")) { data.put("hwid", "SEG-" + UUID.randomUUID().toString().replace("-", "").uppercase()); save(data) }
            when (call.method) {
                "read" -> {
                    var license = ""
                    if (data.has("secret")) {
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(data.getString("iv"), Base64.NO_WRAP)))
                        license = String(cipher.doFinal(Base64.decode(data.getString("secret"), Base64.NO_WRAP)))
                    }
                    result.success(mapOf("hwid" to data.getString("hwid"), "license" to license))
                }
                "save" -> {
                    val license = call.argument<String>("license") ?: ""
                    if (license.isEmpty()) { data.remove("secret"); data.remove("iv") }
                    else {
                        require(Regex("^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$").matches(license))
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        data.put("secret", Base64.encodeToString(cipher.doFinal(license.toByteArray()), Base64.NO_WRAP))
                        data.put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                    }
                    save(data); result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("activation_unavailable", "No se pudo abrir la activación segura.", null) }
    }
}

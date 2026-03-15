package com.example.sync_music

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/// 处理 Android content:// URI 的读取
class ContentResolverHandler(private val context: Context) {
    companion object {
        private const val CHANNEL_NAME = "com.example.sync_music/content_resolver"
        private const val TAG = "ContentResolverHandler"
        
        // 支持的音频扩展名
        private val AUDIO_EXTENSIONS = listOf("mp3", "aac", "m4a", "wav", "flac", "ogg")
        
        fun register(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            val handler = ContentResolverHandler(context)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "readContentUri" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("INVALID_ARGUMENT", "URI is null", null)
                            return@setMethodCallHandler
                        }
                        val bytes = handler.readContentUri(uriString)
                        if (bytes != null) {
                            result.success(bytes)
                        } else {
                            result.error("READ_FAILED", "Failed to read content URI", null)
                        }
                    }
                    "listContentTree" -> {
                        val treeUriString = call.argument<String>("treeUri")
                        if (treeUriString == null) {
                            result.error("INVALID_ARGUMENT", "treeUri is null", null)
                            return@setMethodCallHandler
                        }
                        val files = handler.listContentTree(treeUriString)
                        result.success(files)
                    }
                    else -> result.notImplemented()
                }
            }
            Log.d(TAG, "ContentResolverHandler registered")
        }
    }
    
    /// 读取 content:// URI 并返回字节数组
    fun readContentUri(uriString: String): ByteArray? {
        return try {
            val uri = Uri.parse(uriString)
            val contentResolver: ContentResolver = context.contentResolver
            
            // 打开输入流
            val inputStream = contentResolver.openInputStream(uri)
                ?: run {
                    Log.e(TAG, "Failed to open input stream for URI: $uriString")
                    return null
                }
            
            // 读取全部字节
            val bytes = inputStream.use { it.readBytes() }
            Log.d(TAG, "Read ${bytes.size} bytes from URI: $uriString")
            bytes
        } catch (e: Exception) {
            Log.e(TAG, "Error reading content URI: $uriString", e)
            null
        }
    }
    
    /// 列出 content tree URI 中的音乐文件
    fun listContentTree(treeUriString: String): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        
        try {
            val treeUri = Uri.parse(treeUriString)
            val contentResolver: ContentResolver = context.contentResolver
            
            // 获取 tree document ID
            val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                treeDocumentId
            )
            
            Log.d(TAG, "Listing content tree: $treeUriString, childrenUri: $childrenUri")
            
            // 查询子文件
            val cursor: Cursor? = contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE
                ),
                null,
                null,
                "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} ASC"
            )
            
            cursor?.use {
                val idColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                
                while (it.moveToNext()) {
                    val documentId = it.getString(idColumn)
                    val name = it.getString(nameColumn)
                    
                    // 检查是否是音频文件
                    val extension = name.substringAfterLast('.', "").lowercase()
                    if (extension in AUDIO_EXTENSIONS) {
                        val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                        
                        files.add(mapOf(
                            "uri" to fileUri.toString(),
                            "name" to name,
                            "documentId" to documentId
                        ))
                        
                        Log.d(TAG, "Found audio file: $name, uri: $fileUri")
                    }
                }
            }
            
            Log.d(TAG, "Found ${files.size} audio files in tree")
        } catch (e: Exception) {
            Log.e(TAG, "Error listing content tree: $treeUriString", e)
        }
        
        return files
    }
}

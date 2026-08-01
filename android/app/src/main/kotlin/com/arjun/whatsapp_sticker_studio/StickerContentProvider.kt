package com.arjun.whatsapp_sticker_studio

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File

/**
 * Serves staged sticker packs to WhatsApp over the official third-party sticker API.
 *
 * Deliberately a **dumb reader**: Dart owns the library (drift + files) and stages a pack as
 * `<filesDir>/sticker_packs/<identifier>/` containing `pack.json`, the tray image and the sticker
 * WebPs. Reaching into the app database from Kotlin would duplicate schema knowledge across the
 * language boundary for no gain — the provider only ever needs a snapshot of one exported pack.
 *
 * Mirrors WhatsApp's published sample, with one deliberate deviation: **the `whitelisted`
 * (`avoid_cache`) column is omitted entirely.** WhatsApp staff stated in issue #1089 that the flag
 * is being deprecated in favour of storage that does not re-sync with the source app after import,
 * and ignoring it in 2.25.9.78 broke installed packs widely — apps fixed it by dropping the field.
 * If WhatsApp ever errors on its absence, add it back as 0 rather than 1.
 */
class StickerContentProvider : ContentProvider() {

    companion object {
        const val METADATA = "metadata"
        const val STICKERS = "stickers"
        const val STICKERS_ASSET = "stickers_asset"

        private const val CODE_METADATA_ALL = 1
        private const val CODE_METADATA_SINGLE = 2
        private const val CODE_STICKERS = 3
        private const val CODE_STICKER_ASSET = 4

        // Column names are WhatsApp's contract — do not rename.
        private val METADATA_COLUMNS = arrayOf(
            "sticker_pack_identifier",
            "sticker_pack_name",
            "sticker_pack_publisher",
            "sticker_pack_icon",
            "android_play_store_link",
            "ios_app_download_link",
            "sticker_pack_publisher_email",
            "sticker_pack_publisher_website",
            "sticker_pack_privacy_policy_website",
            "sticker_pack_license_agreement_website",
            "image_data_version",
            "animated_sticker_pack",
        )

        private val STICKER_COLUMNS = arrayOf(
            "sticker_file_name",
            "sticker_emoji",
            "sticker_accessibility_text",
        )

        /** Where Dart stages packs; must match `PackStager` on the Dart side. */
        fun packsDir(root: File) = File(root, "sticker_packs")
    }

    private lateinit var authority: String
    private lateinit var matcher: UriMatcher

    override fun onCreate(): Boolean {
        // Derived from the package name so the manifest and this class cannot drift apart.
        authority = "${context!!.packageName}.stickercontentprovider"
        matcher = UriMatcher(UriMatcher.NO_MATCH).apply {
            addURI(authority, METADATA, CODE_METADATA_ALL)
            addURI(authority, "$METADATA/*", CODE_METADATA_SINGLE)
            addURI(authority, "$STICKERS/*", CODE_STICKERS)
            addURI(authority, "$STICKERS_ASSET/*/*", CODE_STICKER_ASSET)
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? {
        return when (matcher.match(uri)) {
            CODE_METADATA_ALL -> metadataCursor(loadAllPacks())
            CODE_METADATA_SINGLE -> {
                val id = uri.lastPathSegment ?: return null
                metadataCursor(listOfNotNull(loadPack(id)))
            }
            CODE_STICKERS -> {
                val id = uri.lastPathSegment ?: return null
                stickerCursor(loadPack(id))
            }
            else -> null
        }
    }

    /** WhatsApp fetches every sticker and the tray image through this. */
    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        if (matcher.match(uri) != CODE_STICKER_ASSET) return null

        val segments = uri.pathSegments
        if (segments.size != 3) return null
        val identifier = segments[1]
        val fileName = segments[2]

        // Contain reads to one staged pack: a traversal in either segment could otherwise
        // hand out arbitrary app-private files to any app holding the read permission.
        if (identifier.contains('/') || identifier.contains("..")) return null
        if (fileName.contains('/') || fileName.contains("..")) return null

        val file = File(File(packsDir(context!!.filesDir), identifier), fileName)
        if (!file.exists()) return null

        return AssetFileDescriptor(
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY),
            0L,
            AssetFileDescriptor.UNKNOWN_LENGTH,
        )
    }

    private fun loadAllPacks(): List<JSONObject> {
        val dir = packsDir(context!!.filesDir)
        val children = dir.listFiles() ?: return emptyList()
        return children.mapNotNull { loadPack(it.name) }
    }

    private fun loadPack(identifier: String): JSONObject? {
        if (identifier.contains('/') || identifier.contains("..")) return null
        val manifest = File(File(packsDir(context!!.filesDir), identifier), "pack.json")
        if (!manifest.exists()) return null
        return runCatching { JSONObject(manifest.readText()) }.getOrNull()
    }

    private fun metadataCursor(packs: List<JSONObject>): Cursor {
        val cursor = MatrixCursor(METADATA_COLUMNS)
        for (pack in packs) {
            cursor.addRow(
                arrayOf<Any?>(
                    pack.optString("identifier"),
                    pack.optString("name"),
                    pack.optString("publisher"),
                    pack.optString("tray_image_file"),
                    pack.optString("android_play_store_link"),
                    pack.optString("ios_app_store_link"),
                    pack.optString("publisher_email"),
                    pack.optString("publisher_website"),
                    pack.optString("privacy_policy_website"),
                    pack.optString("license_agreement_website"),
                    pack.optString("image_data_version", "1"),
                    if (pack.optBoolean("animated_sticker_pack")) 1 else 0,
                ),
            )
        }
        return cursor
    }

    private fun stickerCursor(pack: JSONObject?): Cursor {
        val cursor = MatrixCursor(STICKER_COLUMNS)
        val stickers = pack?.optJSONArray("stickers") ?: return cursor

        for (i in 0 until stickers.length()) {
            val sticker = stickers.optJSONObject(i) ?: continue
            val emojis = sticker.optJSONArray("emojis")
            val joined = buildString {
                if (emojis != null) {
                    for (j in 0 until emojis.length()) {
                        append(emojis.optString(j))
                        if (j < emojis.length() - 1) append(',')
                    }
                }
            }
            cursor.addRow(
                arrayOf<Any?>(
                    sticker.optString("image_file"),
                    joined,
                    sticker.optString("accessibility_text"),
                ),
            )
        }
        return cursor
    }

    override fun getType(uri: Uri): String? = when (matcher.match(uri)) {
        CODE_METADATA_ALL -> "vnd.android.cursor.dir/vnd.$authority.$METADATA"
        CODE_METADATA_SINGLE -> "vnd.android.cursor.item/vnd.$authority.$METADATA"
        CODE_STICKERS -> "vnd.android.cursor.dir/vnd.$authority.$STICKERS"
        CODE_STICKER_ASSET -> "image/webp"
        else -> null
    }

    // Read-only by contract: WhatsApp only ever queries and opens files.
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int = 0
}

/**
 * SoundCloud Module for 8SPINE - Vanilla JS Version
 */

const SC_CLIENT_ID = 'YOUR_CLIENT_ID_HERE'; // ملاحظة: ستحتاج جلب client_id حقيقي ليعمل البحث

const SoundCloudModule = {
    name: "SoundCloud",
    
    // دالة البحث
    search: async function(query, limit = 10) {
        try {
            // هنا نستخدم API الخاص بـ SoundCloud
            const url = `https://api-v2.soundcloud.com/search/tracks?q=${encodeURIComponent(query)}&client_id=${SC_CLIENT_ID}&limit=${limit}`;
            const response = await fetch(url);
            const data = await response.json();

            if (!data.collection) return [];

            // تحويل النتائج لتنسيق التطبيق
            return data.collection.map(track => ({
                id: track.id.toString(),
                title: track.title,
                artist: track.user ? track.user.username : 'Unknown',
                duration: track.duration / 1000, // تحويل الملي ثانية إلى ثواني
                artwork: track.artwork_url ? track.artwork_url.replace('-large', '-t500x500') : null,
                streamUrl: null
            }));
        } catch (error) {
            console.error("Search error:", error);
            return [];
        }
    },

    // دالة جلب رابط البث
    getStreamUrl: async function(trackId) {
        try {
            // جلب بيانات المسار للحصول على رابط البث
            const trackUrl = `https://api-v2.soundcloud.com/tracks/${trackId}?client_id=${SC_CLIENT_ID}`;
            const response = await fetch(trackUrl);
            const data = await response.json();

            if (data.media && data.media.transcodings) {
                // البحث عن جودة عالية
                const streamInfo = data.media.transcodings.find(t => t.format.protocol === 'progressive' || t.format.mime_type === 'audio/mpeg');
                if (streamInfo) {
                    const streamResponse = await fetch(`${streamInfo.url}?client_id=${SC_CLIENT_ID}`);
                    const streamData = await streamResponse.json();
                    return streamData.url;
                }
            }
            return null;
        } catch (error) {
            console.error("Stream error:", error);
            return null;
        }
    }
};

// تصدير الموديول (قد يختلف حسب طريقة التطبيق)
if (typeof module !== 'undefined' && module.exports) {
    module.exports = SoundCloudModule;
}

/**
 * SoundCloud Module for 8SPINE - Vanilla JS Version (with Client ID)
 */

// معرف العميل (Client ID) الاحتياطي الذي تم الحصول عليه
const SC_CLIENT_ID = 'iFagfuAuwkp6GbI6M6rA7UMw4LOdqC95';

// رؤوس الطلبات (Headers) لمحاكاة المتصفح وتجنب الحظر
const HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Referer': 'https://soundcloud.com/'
};

const SoundCloudModule = {
    name: "SoundCloud",

    // دالة البحث
    search: async function(query, limit = 10) {
        try {
            // البحث باستخدام API v2 مع تمرير الـ client_id
            const url = `https://api-v2.soundcloud.com/search?q=${encodeURIComponent(query)}&client_id=${SC_CLIENT_ID}&limit=${limit}&linked_partitioning=1`;
            
            const response = await fetch(url, { headers: HEADERS });
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            
            const data = await response.json();
            if (!data.collection) return [];

            // تصفية النتائج لاستخراج المسارات (Tracks) فقط
            const tracks = data.collection.filter(item => item.kind === 'track');

            // تحويل النتائج إلى التنسيق المطلوب
            return tracks.map(track => ({
                id: track.id.toString(),
                title: track.title,
                artist: track.user ? track.user.username : 'Unknown Artist',
                duration: track.duration ? track.duration / 1000 : 0, // تحويل الميلي ثانية إلى ثواني
                artwork: track.artwork_url ? track.artwork_url.replace('-large', '-t500x500') : null,
                streamUrl: null // سيتم جلبها لاحقًا
            }));
        } catch (error) {
            console.error("[SoundCloud] Search error:", error);
            return [];
        }
    },

    // دالة جلب رابط البث
    getStreamUrl: async function(trackId) {
        try {
            // 1. جلب تفاصيل المسار للحصول على قائمة الترميزات (transcodings)
            const trackUrl = `https://api-v2.soundcloud.com/tracks/${trackId}?client_id=${SC_CLIENT_ID}`;
            const trackResponse = await fetch(trackUrl, { headers: HEADERS });
            if (!trackResponse.ok) throw new Error(`HTTP error! status: ${trackResponse.status}`);
            
            const trackData = await trackResponse.json();
            
            // 2. البحث عن ترميز "progressive" (ملف MP3 مباشر)
            if (trackData.media && trackData.media.transcodings) {
                const streamInfo = trackData.media.transcodings.find(
                    t => t.format.protocol === 'progressive' || t.format.mime_type === 'audio/mpeg'
                );
                
                if (streamInfo) {
                    // 3. طلب رابط البث النهائي من رابط الترميز
                    const streamResponse = await fetch(`${streamInfo.url}?client_id=${SC_CLIENT_ID}`, { headers: HEADERS });
                    if (!streamResponse.ok) throw new Error(`HTTP error! status: ${streamResponse.status}`);
                    
                    const streamData = await streamResponse.json();
                    return streamData.url; // هذا هو رابط الـ MP3 المباشر
                }
            }
            return null; // لا يوجد ترميز متاح
        } catch (error) {
            console.error("[SoundCloud] Stream error:", error);
            return null;
        }
    }
};

// تصدير الموديول
// إرجاع الكائن مباشرة لبيئة التطبيق
SoundCloudModule;


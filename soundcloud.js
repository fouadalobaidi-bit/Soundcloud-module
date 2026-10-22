/**
 * SoundCloud Module for 8SPINE
 * يعتمد على مكتبة @zibot/scdl غير الرسمية
 * ملاحظة: هذه المكتبة تتطلب بيئة Node.js (أو بيئة مشابهة تدعم fetch والتدفقات).
 */

let SoundCloud;
try {
  // محاولة تحميل المكتبة (في حال كانت متوفرة في بيئة التطبيق)
  SoundCloud = require('@zibot/scdl');
} catch (e) {
  console.error('[SoundCloud Module] مكتبة @zibot/scdl غير مثبتة. يرجى تثبيتها: npm i @zibot/scdl');
}

let sc;

/**
 * تهيئة العميل (يُستدعى مرة واحدة عند تحميل الموديول)
 */
async function initialize() {
  if (!SoundCloud) {
    throw new Error('مكتبة SoundCloud غير متوفرة.');
  }
  // auto-init: جلب clientId تلقائياً
  sc = new SoundCloud({ init: true });
  await sc.init(); // التأكد من التهيئة[reference:1]
  console.log('[SoundCloud Module] تم التهيئة بنجاح.');
}

/**
 * دالة البحث (Search)
 * @param {string} query - نص البحث
 * @param {number} limit - عدد النتائج (افتراضي 10)
 * @returns {Promise<Array>} - مصفوفة من المسارات
 */
async function search(query, limit = 10) {
  if (!sc) await initialize();
  
  try {
    const results = await sc.search({
      query: query,
      limit: limit,
      type: 'tracks' // نبحث عن مسارات فقط[reference:2]
    });

    // تحويل البيانات إلى تنسيق يفهمه 8SPINE (افتراضي)
    return results.map(track => ({
      id: track.id.toString(),
      title: track.title,
      artist: track.user ? track.user.username : 'Unknown Artist',
      duration: track.duration || 0,
      artwork: track.artwork_url || null,
      streamUrl: null // سيتم جلبها لاحقاً عند التشغيل
    }));
  } catch (error) {
    console.error('[SoundCloud Module] خطأ في البحث:', error.message);
    throw error;
  }
}

/**
 * دالة جلب رابط التشغيل (Stream URL)
 * @param {string} trackId - معرف المسار
 * @returns {Promise<string>} - رابط البث الصوتي
 */
async function getStreamUrl(trackId) {
  if (!sc) await initialize();

  try {
    // ملاحظة: مكتبة @zibot/scdl تتوقع رابط المسار أو الـ slug، وليس المعرف الرقمي فقط.
    // في بيئة حقيقية، قد تحتاج إلى تخزين الـ permalink_url أو استخدام طريقة أخرى.
    // هنا نفترض أن trackId هو الرابط الكامل أو يمكن تحويله.
    // للحصول على رابط البث، نستخدم downloadTrack الذي يعيد Readable Stream.
    // لكن 8SPINE قد يتوقع رابط URL مباشر. الحل: استخدام خاصية stream_url إن وجدت.
    // كحل بديل، يمكن استخدام مكتبة أخرى مثل soundcloud-core.
    
    // محاولة الحصول على تفاصيل المسار أولاً
    const trackDetails = await sc.getTrackDetails(trackId);
    
    // إذا كان هناك stream_url جاهز في التفاصيل
    if (trackDetails.stream_url) {
      // غالباً ما يتطلب stream_url إضافة client_id
      return `${trackDetails.stream_url}?client_id=${sc.clientId}`;
    }
    
    // إذا لم يوجد، نستخدم downloadTrack للحصول على stream (قد لا يكون رابطاً مباشراً)
    // هذا الجزء يحتاج تكييفاً حسب ما يتوقعه 8SPINE بالضبط.
    const stream = await sc.downloadTrack(trackId, { quality: 'high' });
    // إذا كان 8SPINE يقبل كائن stream، أرجع Stream. وإلا تحتاج لتحويله إلى URL.
    // هنا نرجع الـ stream ككائن (افتراضاً أن التطبيق يتعامل معه).
    return stream;
    
  } catch (error) {
    console.error('[SoundCloud Module] خطأ في جلب رابط التشغيل:', error.message);
    throw error;
  }
}

/**
 * دالة جلب تفاصيل المسار (اختياري)
 * @param {string} trackId - معرف المسار
 * @returns {Promise<Object>} - تفاصيل المسار
 */
async function getTrackInfo(trackId) {
  if (!sc) await initialize();
  
  try {
    const track = await sc.getTrackDetails(trackId);
    return {
      id: track.id.toString(),
      title: track.title,
      artist: track.user ? track.user.username : 'Unknown Artist',
      duration: track.duration,
      artwork: track.artwork_url,
      genre: track.genre,
      description: track.description
    };
  } catch (error) {
    console.error('[SoundCloud Module] خطأ في جلب تفاصيل المسار:', error.message);
    throw error;
  }
}

// تصدير الدوال لكي يتمكن 8SPINE من استدعاءها
module.exports = {
  initialize,
  search,
  getStreamUrl,
  getTrackInfo
};

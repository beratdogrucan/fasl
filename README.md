# Fasl

Her hikâye bir fasıl ile başlar. Fasl; yazarların eserlerini bölüm bölüm yayımladığı, okurların yeni dünyalar keşfettiği sosyal yazı platformudur.

## Çalıştırma

Node.js 18 veya üzeriyle:

```bash
npm start
```

Ardından `http://localhost:3000` adresini açın.

## İlk sürüm

- Ana sayfa ve tür filtreleri
- Hikâye detay/okuma görünümü
- Yazma stüdyosu ve yerel taslak kaydı
- Giriş/kayıt arayüzü
- Mobil uyumlu tasarım

## Supabase bağlantısı

`supabase/schema.sql` dosyası yeni ve ayrı bir Supabase projesinin SQL Editor ekranında çalıştırılmalıdır. Şema; kullanıcı profilleri, eserler, bölümler, kütüphane, yorumlar, beğeniler ve takipler için tabloları ve satır düzeyi güvenlik kurallarını içerir.

Çizgi'nin Supabase projesini Fasl için yeniden kullanmayın. `.env.example` dosyasını `.env` olarak kopyalayıp Fasl'a ait proje bilgileriyle doldurun; service-role anahtarını hiçbir zaman tarayıcı koduna veya GitHub'a eklemeyin.

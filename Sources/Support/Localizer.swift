import Foundation

/// Tiny in-app localization table (no .strings catalogs, no external dependency).
enum L {
    static let fallback: [String: String] = [
        "browser": "Browser",
        "downloads": "Downloads",
        "media": "Media",
        "favorites": "Favorites",
        "settings": "Settings",
        "history": "History",
        "new_tab": "New Tab",
        "private_tab": "New Private Tab",
        "search_placeholder": "Search or enter website",
        "close_all_tabs": "Close All Tabs",
        "add_to_favorites": "Add to Favorites",
        "download_media": "Download Media from Page",
        "no_media_found": "No media found",
        "no_downloads": "No downloads yet — unlimited, no caps.",
        "no_favorites": "No favorites yet.",
        "no_history": "Nothing visited yet.",
        "block_ads": "Block ads and popups",
        "block_trackers": "Block trackers",
        "default_private": "Open new tabs in Private Mode",
        "clear_data": "Clear browsing data",
        "clear_cache": "Clear cache",
        "about": "Magdy Browser 1.0",
        "reader_mode": "Reader Mode",
        "find_in_page": "Find in Page",
        "next": "Next",
        "previous": "Previous",
        "done": "Done",
        "cancel": "Cancel",
        "clear": "Clear",
        "delete": "Delete",
        "unlimited_note": "Free. Unlimited. No account, no subscription, no download caps.",
        "edit_tags": "Edit Tags",
        "upscale": "Upscale",
        "start": "Start upscaling",
        "language": "Language"
    ]

    private static let table: [String: [String: String]] = [
        "ar": [
            "browser": "المتصفح", "downloads": "التنزيلات", "media": "الوسائط", "favorites": "المفضلة",
            "settings": "الإعدادات", "history": "السجل", "new_tab": "علامة تبويب جديدة",
            "private_tab": "علامة تبويب خاصة", "search_placeholder": "ابحث أو أدخل الموقع",
            "close_all_tabs": "إغلاق كل علامات التبويب", "add_to_favorites": "أض إلى المفضلة",
            "download_media": "تنزيل الوسائط من الصفحة", "no_media_found": "لا توجد وسائط",
            "no_downloads": "لا تنزيلات بعد — بلا حدود.", "no_favorites": "لا مفضلة بعد.",
            "no_history": "لا زيارات بعد.", "block_ads": "حجب الإعلانات والنوافذ",
            "block_trackers": "حجب المتتبعات", "default_private": "فتح علامات تبويب جديدة في وضع التصفح الخاص",
            "clear_data": "مسح بيانات التصفح", "clear_cache": "مسح ذاكرة التخزين المؤقت",
            "about": "ماغدي 1.0", "reader_mode": "وضع القراءة", "find_in_page": "بحث في الصفحة",
            "next": "التالي", "previous": "السابق", "done": "تم", "cancel": "إلغاء", "clear": "مسح",
            "delete": "حذف", "unlimited_note": "مجاني. بلا حدود. بدون حساب أو اشتراك.",
            "edit_tags": "تعديل الوسوم", "upscale": "تكبير", "start": "بدء التكبير", "language": "اللغة"
        ],
        "fr": [
            "browser": "Navigateur", "downloads": "Téléchargements", "media": "Médias",
            "favorites": "Favoris", "settings": "Réglages", "history": "Historique",
            "new_tab": "Nouvel onglet", "private_tab": "Nouvel onglet privé",
            "search_placeholder": "Rechercher ou saisir un site",
            "close_all_tabs": "Fermer tous les onglets", "add_to_favorites": "Ajouter aux favoris",
            "download_media": "Télécharger les médias de la page", "no_media_found": "Aucun média trouvé",
            "no_downloads": "Aucun téléchargement — illimité, sans limite.",
            "no_favorites": "Aucun favori.", "no_history": "Aucune visite.",
            "block_ads": "Bloquer les publicités", "block_trackers": "Bloquer les traceurs",
            "default_private": "Ouvrir les nouveaux onglets en navigation privée",
            "clear_data": "Effacer les données", "clear_cache": "Vider le cache",
            "about": "Magdy Browser 1.0", "reader_mode": "Mode lecture", "find_in_page": "Rechercher dans la page",
            "next": "Suivant", "previous": "Précédent", "done": "Terminé", "cancel": "Annuler",
            "clear": "Effacer", "delete": "Supprimer",
            "unlimited_note": "Gratuit. Illimité. Sans compte ni abonnement.",
            "edit_tags": "Modifier les tags", "upscale": "Agrandir", "start": "Lancer l'agrandissement",
            "language": "Langue"
        ],
        "es": [
            "browser": "Navegador", "downloads": "Descargas", "media": "Multimedia",
            "favorites": "Favoritos", "settings": "Ajustes", "history": "Historial",
            "new_tab": "Pestaña nueva", "private_tab": "Pestaña privada",
            "search_placeholder": "Busca o escribe una dirección",
            "close_all_tabs": "Cerrar todas las pestañas", "add_to_favorites": "Añadir a favoritos",
            "download_media": "Descargar multimedia de la página", "no_media_found": "Sin multimedia",
            "no_downloads": "Sin descargas — ilimitadas, sin límites.",
            "no_favorites": "Sin favoritos.", "no_history": "Sin visitas.",
            "block_ads": "Bloquear anuncios", "block_trackers": "Bloquear rastreadores",
            "default_private": "Abrir pestañas nuevas en modo privado",
            "clear_data": "Borrar datos de navegación", "clear_cache": "Vaciar caché",
            "about": "Magdy Browser 1.0", "reader_mode": "Modo lectura", "find_in_page": "Buscar en la página",
            "next": "Siguiente", "previous": "Anterior", "done": "Hecho", "cancel": "Cancelar",
            "clear": "Borrar", "delete": "Eliminar",
            "unlimited_note": "Gratis. Ilimitado. Sin cuenta ni suscripción.",
            "edit_tags": "Editar etiquetas", "upscale": "Ampliar", "start": "Iniciar ampliación",
            "language": "Idioma"
        ],
        "de": [
            "browser": "Browser", "downloads": "Downloads", "media": "Medien", "favorites": "Favoriten",
            "settings": "Einstellungen", "history": "Verlauf", "new_tab": "Neuer Tab",
            "private_tab": "Neuer privater Tab", "search_placeholder": "Suchen oder Adresse eingeben",
            "close_all_tabs": "Alle Tabs schließen", "add_to_favorites": "Zu Favoriten hinzufügen",
            "download_media": "Medien der Seite laden", "no_media_found": "Keine Medien gefunden",
            "no_downloads": "Noch keine Downloads — unbegrenzt, ohne Limits.",
            "no_favorites": "Noch keine Favoriten.", "no_history": "Noch keine Besuche.",
            "block_ads": "Werbung blockieren", "block_trackers": "Tracker blockieren",
            "default_private": "Neue Tabs im privaten Modus öffnen",
            "clear_data": "Browserdaten löschen", "clear_cache": "Cache leeren",
            "about": "Magdy Browser 1.0", "reader_mode": "Lesemodus", "find_in_page": "In Seite suchen",
            "next": "Weiter", "previous": "Zurück", "done": "Fertig", "cancel": "Abbrechen",
            "clear": "Löschen", "delete": "Löschen",
            "unlimited_note": "Kostenlos. Unbegrenzt. Kein Konto, kein Abo.",
            "edit_tags": "Tags bearbeiten", "upscale": "Hochskalieren", "start": "Hochskalieren starten",
            "language": "Sprache"
        ],
        "tr": [
            "browser": "Tarayıcı", "downloads": "İndirilenler", "media": "Medya", "favorites": "Favoriler",
            "settings": "Ayarlar", "history": "Geçmiş", "new_tab": "Yeni sekme",
            "private_tab": "Yeni gizli sekme", "search_placeholder": "Ara veya adres gir",
            "close_all_tabs": "Tüm sekmeleri kapat", "add_to_favorites": "Favorilere ekle",
            "download_media": "Sayfadaki medyayı indir", "no_media_found": "Medya bulunamadı",
            "no_downloads": "Henüz indirme yok — sınırsız, limitsiz.",
            "no_favorites": "Favori yok.", "no_history": "Henüz ziyaret yok.",
            "block_ads": "Reklamları engelle", "block_trackers": "İzleyicileri engelle",
            "default_private": "Yeni sekmeleri gizli modda aç",
            "clear_data": "Tarama verilerini temizle", "clear_cache": "Önbelleği temizle",
            "about": "Magdy Browser 1.0", "reader_mode": "Okuma modu", "find_in_page": "Sayfada ara",
            "next": "İleri", "previous": "Geri", "done": "Bitti", "cancel": "İptal",
            "clear": "Temizle", "delete": "Sil",
            "unlimited_note": "Ücretsiz. Sınırsız. Hesap yok, abonelik yok.",
            "edit_tags": "Etiketleri düzenle", "upscale": "Yakınlaştır", "start": "Yakınlaştırmayı başlat",
            "language": "Dil"
        ]
    ]

    static var language: String {
        UserDefaults.standard.string(forKey: "magdy.language") ?? "system"
    }

    static var languageTag: String {
        let raw = language == "system" ? (Locale.preferredLanguages.first ?? "en") : language
        let locale = Locale(identifier: raw)
        let base = locale.languageCode?.identifier.lowercased() ?? String(raw.prefix(2)).lowercased()
        if base == "zh", let script = locale.scriptCode?.identifier.lowercased() {
            return "zh-\(script)"
        }
        return base
    }

    static var resolvedLanguage: String {
        String(languageTag.prefix(2))
    }

    static var isRightToLeft: Bool {
        resolvedLanguage == "ar" || resolvedLanguage == "he" || resolvedLanguage == "fa"
    }

    static func t(_ key: String) -> String {
        table[resolvedLanguage]?[key] ?? fallback[key] ?? key
    }
}

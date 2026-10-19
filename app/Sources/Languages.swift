import Foundation
import NaturalLanguage

/// Язык модели NLLB-200, код в формате FLORES-200 (например, rus_Cyrl).
struct Lang: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let favoriteCodes = ["eng_Latn", "rus_Cyrl", "hye_Armn", "deu_Latn", "fra_Latn", "spa_Latn", "por_Latn"]

    /// Все языки, отсортированные по названию. После запуска сервера
    /// список сужается до кодов, которые реально есть в модели.
    private(set) static var all: [Lang] = table
        .split(separator: "\n")
        .compactMap { line -> Lang? in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Lang(code: String(parts[0]), name: String(parts[1]))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static var favorites: [Lang] { favoriteCodes.compactMap(byCode) }

    static func byCode(_ code: String) -> Lang? { all.first { $0.code == code } }

    static func restrict(to codes: Set<String>) {
        let filtered = all.filter { codes.contains($0.code) }
        if !filtered.isEmpty { all = filtered }
    }

    /// Короткий код для интерфейса: EN, RU, HY… (ISO 639-1, если он есть).
    var shortCode: String {
        let iso3 = String(code.prefix(3))
        if let alpha2 = Locale.LanguageCode(iso3).identifier(.alpha2) { return alpha2.uppercased() }
        return iso3.uppercased()
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || name.localizedCaseInsensitiveContains(query)
            || code.localizedCaseInsensitiveContains(query)
    }

    private static let table = """
    ace_Arab|Ачехский (арабское письмо)
    ace_Latn|Ачехский (латиница)
    acm_Arab|Арабский (месопотамский)
    acq_Arab|Арабский (таиззи-аденский)
    aeb_Arab|Арабский (тунисский)
    afr_Latn|Африкаанс
    ajp_Arab|Арабский (южнолевантийский)
    aka_Latn|Акан
    als_Latn|Албанский
    amh_Ethi|Амхарский
    apc_Arab|Арабский (северолевантийский)
    arb_Arab|Арабский (литературный)
    ars_Arab|Арабский (неджды)
    ary_Arab|Арабский (марокканский)
    arz_Arab|Арабский (египетский)
    asm_Beng|Ассамский
    ast_Latn|Астурийский
    awa_Deva|Авадхи
    ayr_Latn|Аймара
    azb_Arab|Азербайджанский (южный)
    azj_Latn|Азербайджанский
    bak_Cyrl|Башкирский
    bam_Latn|Бамана
    ban_Latn|Балийский
    bel_Cyrl|Белорусский
    bem_Latn|Бемба
    ben_Beng|Бенгальский
    bho_Deva|Бходжпури
    bjn_Arab|Банджарский (арабское письмо)
    bjn_Latn|Банджарский (латиница)
    bod_Tibt|Тибетский
    bos_Latn|Боснийский
    bug_Latn|Бугийский
    bul_Cyrl|Болгарский
    cat_Latn|Каталанский
    ceb_Latn|Себуанский
    ces_Latn|Чешский
    cjk_Latn|Чокве
    ckb_Arab|Курдский (сорани)
    crh_Latn|Крымскотатарский
    cym_Latn|Валлийский
    dan_Latn|Датский
    deu_Latn|Немецкий
    dik_Latn|Динка
    dyu_Latn|Дьюла
    dzo_Tibt|Дзонг-кэ
    ell_Grek|Греческий
    eng_Latn|Английский
    epo_Latn|Эсперанто
    est_Latn|Эстонский
    eus_Latn|Баскский
    ewe_Latn|Эве
    fao_Latn|Фарерский
    fij_Latn|Фиджийский
    fin_Latn|Финский
    fon_Latn|Фон
    fra_Latn|Французский
    fur_Latn|Фриульский
    fuv_Latn|Фула (нигерийский)
    gaz_Latn|Оромо
    gla_Latn|Гэльский (шотландский)
    gle_Latn|Ирландский
    glg_Latn|Галисийский
    grn_Latn|Гуарани
    guj_Gujr|Гуджарати
    hat_Latn|Гаитянский креольский
    hau_Latn|Хауса
    heb_Hebr|Иврит
    hin_Deva|Хинди
    hne_Deva|Чхаттисгархи
    hrv_Latn|Хорватский
    hun_Latn|Венгерский
    hye_Armn|Армянский
    ibo_Latn|Игбо
    ilo_Latn|Илоканский
    ind_Latn|Индонезийский
    isl_Latn|Исландский
    ita_Latn|Итальянский
    jav_Latn|Яванский
    jpn_Jpan|Японский
    kab_Latn|Кабильский
    kac_Latn|Качинский
    kam_Latn|Камба
    kan_Knda|Каннада
    kas_Arab|Кашмирский (арабское письмо)
    kas_Deva|Кашмирский (деванагари)
    kat_Geor|Грузинский
    kaz_Cyrl|Казахский
    kbp_Latn|Кабье
    kea_Latn|Кабувердьяну
    khk_Cyrl|Монгольский
    khm_Khmr|Кхмерский
    kik_Latn|Кикуйю
    kin_Latn|Киньяруанда
    kir_Cyrl|Киргизский
    kmb_Latn|Кимбунду
    kmr_Latn|Курдский (курманджи)
    knc_Arab|Канури (арабское письмо)
    knc_Latn|Канури (латиница)
    kon_Latn|Конго
    kor_Hang|Корейский
    lao_Laoo|Лаосский
    lij_Latn|Лигурский
    lim_Latn|Лимбургский
    lin_Latn|Лингала
    lit_Latn|Литовский
    lmo_Latn|Ломбардский
    ltg_Latn|Латгальский
    ltz_Latn|Люксембургский
    lua_Latn|Луба-лулуа
    lug_Latn|Луганда
    luo_Latn|Луо
    lus_Latn|Мизо
    lvs_Latn|Латышский
    mag_Deva|Магахи
    mai_Deva|Майтхили
    mal_Mlym|Малаялам
    mar_Deva|Маратхи
    min_Latn|Минангкабау
    mkd_Cyrl|Македонский
    mlt_Latn|Мальтийский
    mni_Beng|Манипури
    mos_Latn|Мооре
    mri_Latn|Маори
    mya_Mymr|Бирманский
    nld_Latn|Нидерландский
    nno_Latn|Норвежский (нюнорск)
    nob_Latn|Норвежский (букмол)
    npi_Deva|Непальский
    nso_Latn|Северный сото
    nus_Latn|Нуэр
    nya_Latn|Ньянджа
    oci_Latn|Окситанский
    ory_Orya|Ория
    pag_Latn|Пангасинан
    pan_Guru|Панджаби
    pap_Latn|Папьяменто
    pbt_Arab|Пушту
    pes_Arab|Персидский
    plt_Latn|Малагасийский
    pol_Latn|Польский
    por_Latn|Португальский
    prs_Arab|Дари
    quy_Latn|Кечуа
    ron_Latn|Румынский
    run_Latn|Рунди
    rus_Cyrl|Русский
    sag_Latn|Санго
    san_Deva|Санскрит
    sat_Beng|Сантали
    sat_Olck|Сантали
    scn_Latn|Сицилийский
    shn_Mymr|Шанский
    sin_Sinh|Сингальский
    slk_Latn|Словацкий
    slv_Latn|Словенский
    smo_Latn|Самоанский
    sna_Latn|Шона
    snd_Arab|Синдхи
    som_Latn|Сомалийский
    sot_Latn|Южный сото
    spa_Latn|Испанский
    srd_Latn|Сардинский
    srp_Cyrl|Сербский
    ssw_Latn|Свази
    sun_Latn|Сунданский
    swe_Latn|Шведский
    swh_Latn|Суахили
    szl_Latn|Силезский
    tam_Taml|Тамильский
    taq_Latn|Тамашек (латиница)
    taq_Tfng|Тамашек (тифинаг)
    tat_Cyrl|Татарский
    tel_Telu|Телугу
    tgk_Cyrl|Таджикский
    tgl_Latn|Тагальский
    tha_Thai|Тайский
    tir_Ethi|Тигринья
    tpi_Latn|Ток-писин
    tsn_Latn|Тсвана
    tso_Latn|Тсонга
    tuk_Latn|Туркменский
    tum_Latn|Тумбука
    tur_Latn|Турецкий
    twi_Latn|Тви
    tzm_Tfng|Тамазигхтский
    uig_Arab|Уйгурский
    ukr_Cyrl|Украинский
    umb_Latn|Умбунду
    urd_Arab|Урду
    uzn_Latn|Узбекский
    vec_Latn|Венетский
    vie_Latn|Вьетнамский
    war_Latn|Варайский
    wol_Latn|Волоф
    xho_Latn|Коса
    ydd_Hebr|Идиш
    yor_Latn|Йоруба
    yue_Hant|Кантонский
    zho_Hans|Китайский (упрощённый)
    zho_Hant|Китайский (традиционный)
    zsm_Latn|Малайский
    zul_Latn|Зулу
    """
}

enum LanguageDetector {
    /// Коды Apple NaturalLanguage → коды NLLB. Языки вне этого списка выбираются вручную.
    private static let appleToNLLB: [String: String] = [
        "am": "amh_Ethi", "ar": "arb_Arab", "hy": "hye_Armn", "bn": "ben_Beng", "bg": "bul_Cyrl",
        "my": "mya_Mymr", "ca": "cat_Latn", "hr": "hrv_Latn", "cs": "ces_Latn", "da": "dan_Latn",
        "nl": "nld_Latn", "en": "eng_Latn", "fi": "fin_Latn", "fr": "fra_Latn", "ka": "kat_Geor",
        "de": "deu_Latn", "el": "ell_Grek", "gu": "guj_Gujr", "he": "heb_Hebr", "hi": "hin_Deva",
        "hu": "hun_Latn", "is": "isl_Latn", "id": "ind_Latn", "it": "ita_Latn", "ja": "jpn_Jpan",
        "kn": "kan_Knda", "kk": "kaz_Cyrl", "km": "khm_Khmr", "ko": "kor_Hang", "lo": "lao_Laoo",
        "ms": "zsm_Latn", "ml": "mal_Mlym", "mr": "mar_Deva", "mn": "khk_Cyrl", "nb": "nob_Latn",
        "no": "nob_Latn", "or": "ory_Orya", "fa": "pes_Arab", "pl": "pol_Latn", "pt": "por_Latn",
        "pa": "pan_Guru", "ro": "ron_Latn", "ru": "rus_Cyrl", "zh-Hans": "zho_Hans", "si": "sin_Sinh",
        "sk": "slk_Latn", "es": "spa_Latn", "sv": "swe_Latn", "ta": "tam_Taml", "te": "tel_Telu",
        "th": "tha_Thai", "bo": "bod_Tibt", "zh-Hant": "zho_Hant", "tr": "tur_Latn", "uk": "ukr_Cyrl",
        "ur": "urd_Arab", "vi": "vie_Latn", "kk-Cyrl": "kaz_Cyrl", "uz": "uzn_Latn", "ckb": "ckb_Arab",
        "ky": "kir_Cyrl", "tg": "tgk_Cyrl", "tk": "tuk_Latn", "az": "azj_Latn", "be": "bel_Cyrl",
        "lt": "lit_Latn", "lv": "lvs_Latn", "et": "est_Latn", "sl": "slv_Latn", "sr": "srp_Cyrl",
        "mk": "mkd_Cyrl", "sq": "als_Latn", "af": "afr_Latn", "sw": "swh_Latn", "tl": "tgl_Latn",
    ]

    static func detect(_ text: String) -> Lang? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1000)))
        guard let best = recognizer.dominantLanguage,
              let code = appleToNLLB[best.rawValue]
        else { return nil }
        return Lang.byCode(code)
    }
}

/// Настройки, как в DeepL: всё переводится на основной язык,
/// а текст на основном языке — на запасной.
enum Settings {
    private static let d = UserDefaults.standard

    static var primaryTarget: Lang {
        get { Lang.byCode(d.string(forKey: "primaryTarget") ?? "") ?? Lang.byCode("rus_Cyrl")! }
        set { d.set(newValue.code, forKey: "primaryTarget") }
    }

    static var secondaryTarget: Lang {
        get { Lang.byCode(d.string(forKey: "secondaryTarget") ?? "") ?? Lang.byCode("eng_Latn")! }
        set { d.set(newValue.code, forKey: "secondaryTarget") }
    }

    static func target(for source: Lang?) -> Lang {
        source == primaryTarget ? secondaryTarget : primaryTarget
    }

    static let port = 8765
}

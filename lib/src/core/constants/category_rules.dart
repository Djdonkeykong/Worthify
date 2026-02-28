/// 🧩 Category classification intelligence for Worthify
/// ----------------------------------------------------
/// Centralized rule set used by DetectionService._categorize()
/// and related garment recognition logic.
/// 
/// This combines:
///   - Keyword mappings
///   - Context-aware overrides
///   - Brand/category hints
///   - Stopword filtering

// =====================================================
// 🧠 CATEGORY KEYWORDS (broad coverage)
// =====================================================

const Map<String, List<String>> kCategoryKeywords = {
  'dresses': [
    'dress',
    'gown',
    'jumpsuit',
    'romper',
    'one-piece',
    'one piece',
    'bodysuit',
    'maxi dress',
    'midi dress',
    'mini dress',
    'evening dress',
    'cocktail dress',
  ],
  'tops': [
    'top',
    'shirt',
    't-shirt',
    'tee',
    'tank',
    'blouse',
    'polo',
    'sweater',
    'hoodie',
    'crewneck',
    'jumper',
    'camisole',
    'cardigan',
    'tunic',
    'long sleeve',
  ],
  'bottoms': [
    'jeans',
    'pants',
    'trouser',
    'shorts',
    'skirt',
    'leggings',
    'cargo',
    'chino',
    'culotte',
    'sweatpants',
    'jogger',
    'denim',
  ],
  'outerwear': [
    'coat',
    'jacket',
    'blazer',
    'vest',
    'trench',
    'puffer',
    'windbreaker',
    'parka',
    'anorak',
    'raincoat',
  ],
  'shoes': [
    'shoe',
    'sneaker',
    'boot',
    'heel',
    'loafer',
    'flat',
    'sandal',
    'slipper',
    'moccasin',
    'trainer',
    'wedge',
    'platform',
    'flip-flop',
    'clog',
    'oxford',
    'derby',
    'running shoe',
    'tennis shoe',
    'high top',
    'low top',
    'slide',
  ],
  'bags': [
    'bag',
    'handbag',
    'tote',
    'crossbody',
    'backpack',
    'satchel',
    'clutch',
    'duffel',
    'wallet',
    'purse',
    'briefcase',
  ],
  'headwear': [
    'hat',
    'cap',
    'beanie',
    'beret',
    'visor',
    'bucket hat',
    'headband',
  ],
  'accessories': [
    'scarf',
    'belt',
    'glasses',
    'sunglasses',
    'watch',
    'earring',
    'necklace',
    'bracelet',
    'ring',
    'tie',
    'bowtie',
    'pin',
    'brooch',
    'glove',
    'keychain',
    'wallet',
  ],
};

// =====================================================
// 🧩 CONTEXTUAL OVERRIDES (fixes ambiguous terms)
// =====================================================

const Map<String, String> kCategoryOverrides = {
  // --- Bottoms ---
  'dress pants': 'bottoms',
  'trousers': 'bottoms',
  'chinos': 'bottoms',
  'cargo pants': 'bottoms',
  'sweatpants': 'bottoms',
  'slacks': 'bottoms',

  // --- Dresses ---
  'jumpsuit': 'dresses',
  'romper': 'dresses',
  'one piece': 'dresses',
  'bodysuit': 'dresses',

  // --- Shoes ---
  'high top': 'shoes',
  'low top': 'shoes',
  'running shoe': 'shoes',
  'tennis shoe': 'shoes',
  'trainers': 'shoes',
  'slides': 'shoes',
  'flip flop': 'shoes',
  'crocs': 'shoes',
  'cleats': 'shoes',

  // --- Outerwear ---
  'denim jacket': 'outerwear',
  'leather jacket': 'outerwear',
  'bomber jacket': 'outerwear',
  'varsity jacket': 'outerwear',
  'puffer jacket': 'outerwear',

  // --- Accessories ---
  'eyewear': 'accessories',
  'sunglass': 'accessories',
  'handkerchief': 'accessories',
  'keychain': 'accessories',
  'wallet': 'accessories',
  'watch': 'accessories',
  'cap': 'headwear',
};

// =====================================================
// 🏷️ BRAND-BASED CATEGORY HINTS
// =====================================================
/// Certain brands heavily imply a specific product type.
/// These help when the title text is vague or missing keywords.
const Map<String, String> kBrandCategoryHints = {
  // --- Footwear brands ---
  'nike': 'shoes',
  'adidas': 'shoes',
  'puma': 'shoes',
  'vans': 'shoes',
  'converse': 'shoes',
  'new balance': 'shoes',
  'reebok': 'shoes',
  'asics': 'shoes',
  'salomon': 'shoes',
  'hoka': 'shoes',
  'crocs': 'shoes',
  'dr martens': 'shoes',
  'timberland': 'shoes',

  // --- Bags & accessories ---
  'coach': 'bags',
  'michael kors': 'bags',
  'kate spade': 'bags',
  'tory burch': 'bags',
  'longchamp': 'bags',
  'rimowa': 'bags',
  'samsonite': 'bags',
  'away': 'bags',
  'herschel': 'bags',

  // --- Apparel-heavy brands ---
  'zara': 'tops',
  'h&m': 'tops',
  'uniqlo': 'tops',
  'asos': 'tops',
  'shein': 'tops',
  'fashion nova': 'tops',
  'boohoo': 'tops',
  'revolve': 'dresses',
  'princess polly': 'dresses',
  'lulus': 'dresses',
  'prettylittlething': 'dresses',

  // --- Outerwear specialists ---
  'north face': 'outerwear',
  'columbia': 'outerwear',
  'patagonia': 'outerwear',
  'canada goose': 'outerwear',
  'moncler': 'outerwear',

  // --- Eyewear & jewelry ---
  'ray-ban': 'accessories',
  'oakley': 'accessories',
  'warby parker': 'accessories',
  'pandora': 'accessories',
  'tiffany': 'accessories',
  'cartier': 'accessories',
  'swarovski': 'accessories',
};

// =====================================================
// 🚫 STOP WORDS
// =====================================================

const Set<String> kCategoryStopWords = {
  'the',
  'and',
  'with',
  'for',
  'from',
  'by',
  'men',
  'women',
  'kids',
  'unisex',
  'fashion',
  'style',
  'clothing',
  'apparel',
  'brand',
  'store',
  'shop',
  'official',
  'new',
  'sale',
  'discount',
  'collection',
  'edition',
};

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ACTUAL ONBOARDING FLOW - Used in production
// Style direction - "Which styles do you like?" (multi-select)
// Options: Streetwear, Minimal, Casual, Classic, Bold, Everything
final styleDirectionProvider = StateProvider<List<String>>((ref) => []);

// What you want - "What are you mostly looking for?" (multi-select)
// Options: Outfits, Shoes, Tops, Accessories, Everything
final whatYouWantProvider = StateProvider<List<String>>((ref) => []);

// Budget - "What price range feels right?" (single select)
// Options: Affordable, Mid-range, Premium, It varies
final budgetProvider = StateProvider<String?>((ref) => null);

// UNUSED LEGACY PROVIDERS - Old onboarding pages (not in current flow)
// Kept to avoid breaking compilation for unused pages
final ageRangeProvider = StateProvider<String?>((ref) => null);
final stylePreferencesProvider = StateProvider<List<String>>((ref) => []);
final preferredRetailersProvider = StateProvider<List<String>>((ref) => []);
final priceRangeProvider = StateProvider<String?>((ref) => null);
final categoryInterestsProvider = StateProvider<List<String>>((ref) => []);
final shoppingFrequencyProvider = StateProvider<String?>((ref) => null);

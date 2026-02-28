"""
Supabase client for Worthify backend.
Handles all database operations including caching, user history, and favorites.

IMPORTANT: Users MUST be authenticated via Supabase Auth before using these APIs.
The iOS app handles authentication and sends the auth user ID.
"""

import os
from typing import Optional, Dict, Any, List
from supabase import create_client, Client
from datetime import datetime, timedelta, timezone

# Get Supabase credentials from environment
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")  # Service role key for server

class SupabaseManager:
    """Singleton manager for Supabase operations"""

    _instance: Optional['SupabaseManager'] = None
    _client: Optional[Client] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if self._client is None:
            if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
                print("WARNING: Supabase credentials not found in environment")
                print("Set SUPABASE_URL and SUPABASE_SERVICE_KEY to enable caching")
                self._client = None
            else:
                self._client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
                print("Supabase client initialized")

    @property
    def client(self) -> Optional[Client]:
        return self._client

    @property
    def enabled(self) -> bool:
        return self._client is not None

    # ============================================
    # IMAGE CACHE OPERATIONS
    # ============================================

    def check_cache_by_source(self, source_url: str) -> Optional[Dict[str, Any]]:
        """
        Check if we've already analyzed this Instagram/source URL.
        Returns cache entry if found and not expired, None otherwise.
        """
        if not self.enabled:
            return None

        try:
            # Normalize Instagram URLs to handle query parameters like ?igsh=
            normalized_url = self._normalize_instagram_url(source_url)

            # Find a user_search with this source_url
            # Check both original and normalized URLs for Instagram
            query_filter = f'source_url.eq.{source_url}'
            if normalized_url != source_url:
                # If URL was normalized (has query params), check both versions
                query_filter = f'source_url.eq.{source_url},source_url.eq.{normalized_url}'

            response = self.client.table('user_searches')\
                .select('image_cache_id, image_cache(*)')\
                .or_(query_filter)\
                .order('created_at', desc=True)\
                .limit(1)\
                .execute()

            if response.data and len(response.data) > 0:
                search = response.data[0]
                cache_data = search.get('image_cache')

                if cache_data:
                    # Check if cache is still valid
                    expires_at_str = cache_data.get('expires_at')
                    if expires_at_str:
                        expires_at = datetime.fromisoformat(expires_at_str.replace('Z', '+00:00'))
                        if expires_at > datetime.now(expires_at.tzinfo):
                            print(f"Cache HIT for Instagram URL: {source_url[:50]}... (normalized: {normalized_url[:50]}...)")
                            return cache_data

            print(f"Instagram cache MISS for URL: {source_url} (normalized: {normalized_url})")
            return None

        except Exception as e:
            print(f"Cache check by source error: {e}")
            return None

    def check_cache(self, image_url: Optional[str] = None, image_hash: Optional[str] = None, country: str = 'US') -> Optional[Dict[str, Any]]:
        """
        Check if image exists in cache by URL or hash for a specific country.
        Returns cache entry if found and not expired, None otherwise.

        Args:
            image_url: URL of the image to check
            image_hash: Hash of the image to check
            country: Country code (e.g., 'US', 'GB', 'FR') - results are country-specific
        """
        if not self.enabled:
            return None

        try:
            # Try to find by URL first (fastest) - must match country
            if image_url:
                response = self.client.table('image_cache')\
                    .select('*')\
                    .eq('image_url', image_url)\
                    .eq('country', country)\
                    .gt('expires_at', datetime.now().isoformat())\
                    .limit(1)\
                    .execute()

                if response.data and len(response.data) > 0:
                    print(f"Cache HIT for URL in {country}: {image_url[:50]}...")
                    return response.data[0]

            # Try by hash if URL miss - must match country
            if image_hash:
                response = self.client.table('image_cache')\
                    .select('*')\
                    .eq('image_hash', image_hash)\
                    .eq('country', country)\
                    .gt('expires_at', datetime.now().isoformat())\
                    .limit(1)\
                    .execute()

                if response.data and len(response.data) > 0:
                    print(f"Cache HIT for hash in {country}: {image_hash[:16]}...")
                    return response.data[0]

            print(f"Cache MISS for image in {country}")
            return None

        except Exception as e:
            print(f"Cache check error: {e}")
            return None

    def store_cache(
        self,
        image_url: Optional[str],
        image_hash: str,
        cloudinary_url: str,
        detected_garments: List[Dict],
        search_results: List[Dict],
        country: str = 'US',
        expires_in_days: int = 30
    ) -> Optional[str]:
        """
        Store analysis results in cache for a specific country.
        Returns cache ID if successful, None otherwise.

        Args:
            image_url: URL of the image
            image_hash: Hash of the image
            cloudinary_url: Cloudinary URL of the processed image
            detected_garments: List of detected garments
            search_results: List of search results
            country: Country code (e.g., 'US', 'GB', 'FR') - results are country-specific
            expires_in_days: Number of days before cache expires
        """
        if not self.enabled:
            return None

        try:
            expires_at = datetime.now() + timedelta(days=expires_in_days)

            cache_entry = {
                'image_url': image_url,
                'image_hash': image_hash,
                'cloudinary_url': cloudinary_url,
                'detected_garments': detected_garments,
                'search_results': search_results,
                'total_results': len(search_results),
                'country': country,
                'expires_at': expires_at.isoformat(),
                'cache_hits': 0
            }

            response = self.client.table('image_cache')\
                .insert(cache_entry)\
                .execute()

            if response.data:
                cache_id = response.data[0]['id']
                print(f"Stored in cache for {country}: {cache_id}")
                return cache_id

            return None

        except Exception as e:
            print(f"Cache store error: {e}")
            return None

    def increment_cache_hit(self, cache_id: str):
        """Increment cache hit counter"""
        if not self.enabled:
            return

        try:
            self.client.rpc('increment_cache_hit', {'cache_id': cache_id}).execute()
        except Exception as e:
            print(f"Cache hit increment error: {e}")

    # ============================================
    # INSTAGRAM URL CACHE OPERATIONS
    # ============================================

    def check_instagram_url_cache(self, instagram_url: str) -> Optional[str]:
        """
        Check if we've already scraped this Instagram URL.
        Returns cached image URL if found, None otherwise.
        """
        if not self.enabled:
            return None

        try:
            # Normalize the URL (remove query params like ?igsh=...)
            normalized_url = self._normalize_instagram_url(instagram_url)

            # Check both original and normalized URLs
            response = self.client.table('instagram_url_cache')\
                .select('image_url, id')\
                .or_(f'instagram_url.eq.{instagram_url},normalized_url.eq.{normalized_url}')\
                .limit(1)\
                .execute()

            if response.data and len(response.data) > 0:
                image_url = response.data[0]['image_url']
                cache_id = response.data[0]['id']
                print(f"Instagram cache HIT for URL: {normalized_url}")

                # Update access tracking
                self._update_instagram_cache_access(cache_id)

                return image_url

            print(f"Instagram cache MISS for URL: {normalized_url}")
            return None

        except Exception as e:
            print(f"Instagram cache check error: {e}")
            return None

    def save_instagram_url_cache(
        self,
        instagram_url: str,
        image_url: str,
        extraction_method: str = 'scrapingbee'
    ) -> Optional[int]:
        """
        Save Instagram URL and extracted image URL to cache.
        Returns cache ID if successful, None otherwise.
        """
        if not self.enabled:
            return None

        try:
            normalized_url = self._normalize_instagram_url(instagram_url)

            cache_entry = {
                'instagram_url': instagram_url,
                'normalized_url': normalized_url,
                'image_url': image_url,
                'extraction_method': extraction_method,
                'access_count': 1
            }

            try:
                response = self.client.table('instagram_url_cache')\
                    .upsert(cache_entry, on_conflict='normalized_url')\
                    .execute()
            except Exception as e:
                error_text = str(e)
                if '42P10' in error_text or 'no unique or exclusion constraint' in error_text:
                    response = None
                else:
                    raise

            if response is None:
                existing = self.client.table('instagram_url_cache')\
                    .select('id')\
                    .eq('normalized_url', normalized_url)\
                    .limit(1)\
                    .execute()

                if existing.data and len(existing.data) > 0:
                    cache_id = existing.data[0]['id']
                    self.client.table('instagram_url_cache')\
                        .update({
                            'instagram_url': instagram_url,
                            'image_url': image_url,
                            'extraction_method': extraction_method,
                            'last_accessed_at': datetime.now().isoformat()
                        })\
                        .eq('id', cache_id)\
                        .execute()
                    print(f"Updated Instagram URL cache: {normalized_url} -> {image_url[:50]}...")
                    return cache_id

                response = self.client.table('instagram_url_cache')\
                    .insert(cache_entry)\
                    .execute()

            if response.data and len(response.data) > 0:
                cache_id = response.data[0]['id']
                print(f"Saved Instagram URL to cache: {normalized_url} -> {image_url[:50]}...")
                return cache_id

            return None

        except Exception as e:
            print(f"Instagram cache save error: {e}")
            return None

    def _normalize_instagram_url(self, url: str) -> str:
        """Normalize Instagram URL by removing query parameters"""
        try:
            from urllib.parse import urlparse
            parsed = urlparse(url)
            # Keep only scheme, netloc, and path
            return f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
        except Exception:
            return url

    def _update_instagram_cache_access(self, cache_id: int):
        """Update last_accessed_at timestamp for Instagram cache entry"""
        if not self.enabled:
            return

        try:
            # Use PostgreSQL function to increment atomically
            self.client.rpc('increment_instagram_cache_access', {
                'cache_entry_id': cache_id
            }).execute()
        except Exception as e:
            # Fallback to manual update if function doesn't exist
            try:
                self.client.table('instagram_url_cache')\
                    .update({'last_accessed_at': datetime.now().isoformat()})\
                    .eq('id', cache_id)\
                    .execute()
            except Exception as fallback_error:
                print(f"Instagram cache access update error: {e}, fallback error: {fallback_error}")

    # ============================================
    # USER SEARCH HISTORY
    # ============================================

    def create_user_search(
        self,
        user_id: str,
        image_cache_id: str,
        search_type: str,
        source_url: Optional[str] = None,
        source_username: Optional[str] = None
    ) -> Optional[str]:
        """
        Create a user search history entry.
        user_id must be a valid auth.users.id
        Returns search_id if successful.
        """
        if not self.enabled:
            return None

        try:
            # Normalize Instagram URLs to remove query parameters
            normalized_source_url = self._normalize_instagram_url(source_url) if source_url else None

            search_entry = {
                'user_id': user_id,
                'image_cache_id': image_cache_id,
                'search_type': search_type,
                'source_url': normalized_source_url,
                'source_username': source_username
            }

            response = self.client.table('user_searches')\
                .insert(search_entry)\
                .execute()

            if response.data:
                search_id = response.data[0]['id']
                print(f"Created user search: {search_id}")
                return search_id

            return None

        except Exception as e:
            print(f"User search creation error: {e}")
            return None

    def create_or_update_user_search(
        self,
        user_id: str,
        image_cache_id: str,
        search_type: str,
        source_url: Optional[str] = None,
        source_username: Optional[str] = None
    ) -> Optional[str]:
        """
        Create or update a user search history entry.
        If the user already has a search for this image_cache_id, update its timestamp.
        Otherwise create a new entry.
        Returns search_id if successful.
        """
        if not self.enabled:
            return None

        try:
            # Check if user already has a search for this cache
            existing = self.client.table('user_searches')\
                .select('id')\
                .eq('user_id', user_id)\
                .eq('image_cache_id', image_cache_id)\
                .limit(1)\
                .execute()

            if existing.data and len(existing.data) > 0:
                # Update existing entry's timestamp to move it to top of history
                search_id = existing.data[0]['id']
                # Use UTC timestamp with timezone info for proper ordering
                utc_now = datetime.now(timezone.utc).isoformat()
                self.client.table('user_searches')\
                    .update({'created_at': utc_now})\
                    .eq('id', search_id)\
                    .execute()
                print(f"Updated existing user search: {search_id} with timestamp {utc_now}")
                return search_id
            else:
                # Create new entry
                return self.create_user_search(
                    user_id=user_id,
                    image_cache_id=image_cache_id,
                    search_type=search_type,
                    source_url=source_url,
                    source_username=source_username
                )

        except Exception as e:
            print(f"User search create/update error: {e}")
            return None

    def get_user_searches(
        self,
        user_id: str,
        limit: int = 20,
        offset: int = 0
    ) -> List[Dict[str, Any]]:
        """Get user's search history with cache data"""
        if not self.enabled:
            return []

        try:
            response = self.client.from_('v_user_recent_searches')\
                .select('*')\
                .eq('user_id', user_id)\
                .order('created_at', desc=True)\
                .range(offset, offset + limit - 1)\
                .execute()

            return response.data or []

        except Exception as e:
            print(f"Get user searches error: {e}")
            return []

    # ============================================
    # FAVORITES - Using existing 'favorites' table
    # ============================================

    def add_favorite(
        self,
        user_id: str,
        product_id: str,
        product_name: str,
        brand: str,
        price: float,
        image_url: str,
        purchase_url: Optional[str],
        category: str
    ) -> Optional[str]:
        """
        Add a product to favorites table.
        user_id must be a valid auth.users.id
        """
        if not self.enabled:
            return None

        try:
            favorite_entry = {
                'user_id': user_id,
                'product_id': product_id,
                'product_name': product_name,
                'brand': brand,
                'price': price,
                'image_url': image_url,
                'purchase_url': purchase_url,
                'category': category
            }

            response = self.client.table('user_favorites')\
                .insert(favorite_entry)\
                .execute()

            if response.data:
                favorite_id = response.data[0]['id']
                print(f"Added favorite: {favorite_id}")
                return favorite_id

            return None

        except Exception as e:
            # Handle unique constraint violation (already favorited)
            if 'duplicate key' in str(e):
                print(f"Product already favorited by user")
                return None
            print(f"Add favorite error: {e}")
            return None

    def get_existing_favorite(
        self,
        user_id: str,
        product_id: str
    ) -> Optional[Dict[str, Any]]:
        """
        Check if a favorite already exists for this user and product.
        Returns the favorite entry if it exists, None otherwise.
        """
        if not self.enabled:
            return None

        try:
            response = self.client.table('user_favorites')\
                .select('*')\
                .eq('user_id', user_id)\
                .eq('product_id', product_id)\
                .limit(1)\
                .execute()

            if response.data and len(response.data) > 0:
                return response.data[0]

            return None

        except Exception as e:
            print(f"Get existing favorite error: {e}")
            return None

    def remove_favorite(self, user_id: str, favorite_id: str) -> bool:
        """Remove a favorite"""
        if not self.enabled:
            return False

        try:
            response = self.client.table('user_favorites')\
                .delete()\
                .eq('id', favorite_id)\
                .eq('user_id', user_id)\
                .execute()

            return True

        except Exception as e:
            print(f"Remove favorite error: {e}")
            return False

    def get_user_favorites(
        self,
        user_id: str,
        limit: int = 50,
        offset: int = 0
    ) -> List[Dict[str, Any]]:
        """Get user's favorites from user_favorites table"""
        if not self.enabled:
            return []

        try:
            response = self.client.table('user_favorites')\
                .select('*')\
                .eq('user_id', user_id)\
                .order('created_at', desc=True)\
                .range(offset, offset + limit - 1)\
                .execute()

            return response.data or []

        except Exception as e:
            print(f"Get user favorites error: {e}")
            return []

    def check_favorited_products(
        self,
        user_id: str,
        product_ids: List[str]
    ) -> List[str]:
        """
        Check which product IDs from the list are already favorited by this user.
        Returns a list of product_ids that exist in user_favorites.
        """
        if not self.enabled or not product_ids:
            return []

        try:
            response = self.client.table('user_favorites')\
                .select('product_id')\
                .eq('user_id', user_id)\
                .in_('product_id', product_ids)\
                .execute()

            if response.data:
                return [fav['product_id'] for fav in response.data]

            return []

        except Exception as e:
            print(f"Check favorited products error: {e}")
            return []

    # ============================================
    # SAVED SEARCHES
    # ============================================

    def save_search(
        self,
        user_id: str,
        search_id: str,
        name: Optional[str] = None
    ) -> Optional[str]:
        """Save an entire search"""
        if not self.enabled:
            return None

        try:
            saved_entry = {
                'user_id': user_id,
                'search_id': search_id,
                'name': name
            }

            response = self.client.table('user_saved_searches')\
                .insert(saved_entry)\
                .execute()

            if response.data:
                saved_id = response.data[0]['id']
                print(f"Saved search: {saved_id}")
                return saved_id

            return None

        except Exception as e:
            # Handle unique constraint (already saved)
            if 'duplicate key' in str(e):
                print(f"Search already saved by user")
                return None
            print(f"Save search error: {e}")
            return None

    def unsave_search(self, user_id: str, saved_search_id: str) -> bool:
        """Unsave a search"""
        if not self.enabled:
            return False

        try:
            response = self.client.table('user_saved_searches')\
                .delete()\
                .eq('id', saved_search_id)\
                .eq('user_id', user_id)\
                .execute()

            return True

        except Exception as e:
            print(f"Unsave search error: {e}")
            return False


# Singleton instance
supabase_manager = SupabaseManager()

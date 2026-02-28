# Security Policy

## Environment Variables

This project uses environment variables to store sensitive configuration data such as API keys and database credentials.

### Setup for Development

1. Copy `.env.example` to `.env`
2. Fill in your actual API keys and credentials
3. Never commit the `.env` file to version control

### Production Deployment

For production deployments, set environment variables through your deployment platform:

```bash
# Supabase
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key

# Replicate
REPLICATE_API_KEY=your_replicate_api_key
REPLICATE_MODEL_VERSION=your_model_version
```

### Running with Environment Variables

```bash
# Development
flutter run --dart-define-from-file=.env

# Production build
flutter build apk --dart-define-from-file=production.env
```

## Reporting Security Issues

If you discover a security vulnerability, please email us privately rather than opening a public issue.

## Security Measures

- All sensitive data is stored in environment variables
- API keys are never committed to the repository
- Regular dependency updates to address security vulnerabilities
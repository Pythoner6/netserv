from os import environ
import sys

pg_host, pg_port, pg_db, pg_user, pg_pass = environ.get('PGPASS', '').split(':')

ALLOWED_HOSTS = ['*']
DATABASE = {
    'NAME': pg_db,
    'USER': pg_user,
    'PASSWORD': pg_pass.strip(),
    'HOST': pg_host,
    'PORT': pg_port,
    'CONN_MAX_AGE': 300,
}
REDIS = {
    'tasks': {
        'SENTINELS': [(environ.get('SENTINEL_SERVICE_NAME'), int(environ.get('SENTINEL_PORT')))],
        'SENTINEL_SERVICE': environ.get('SENTINEL_MASTER_NAME'),
        'PASSWORD': environ.get('REDIS_PASSWORD'),
        'DATABASE': 1,
        'SSL': False,
    },
    'caching': {
        'SENTINELS': [(environ.get('SENTINEL_SERVICE_NAME'), int(environ.get('SENTINEL_PORT')))],
        'SENTINEL_SERVICE': environ.get('SENTINEL_MASTER_NAME'),
        'PASSWORD': environ.get('REDIS_PASSWORD'),
        'DATABASE': 1,
        'SSL': False,
    }
}
SECRET_KEY=environ.get('SECRET_KEY')

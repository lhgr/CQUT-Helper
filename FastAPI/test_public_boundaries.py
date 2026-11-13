import asyncio
import os
import threading
import unittest
from unittest.mock import AsyncMock, Mock, patch
from starlette.requests import Request
from FastAPI.service_common import BodyLimitMiddleware, ServiceError
from FastAPI import jwxt_automation as jwxt


class BodyTests(unittest.IsolatedAsyncioTestCase):
    async def test_chunk_limit_stops_without_consuming_remaining_messages(self):
        receive = AsyncMock(side_effect=[{'type':'http.request','body':b'x'*20480,'more_body':True}, {'type':'http.request','body':b'x','more_body':True}, AssertionError('must not read')])
        send, downstream = AsyncMock(), AsyncMock()
        await BodyLimitMiddleware(downstream)({'type':'http','path':'/api/jwxt/x','headers':[]}, receive, send)
        self.assertEqual(2, receive.await_count)
        self.assertEqual(413, send.call_args_list[0].args[0]['status'])
        downstream.assert_not_awaited()

    async def test_total_body_deadline(self):
        async def slow():
            await asyncio.sleep(.1)
            return {'type':'http.request','body':b''}
        send = AsyncMock()
        await BodyLimitMiddleware(AsyncMock(), read_timeout=.01)({'type':'http','path':'/x','headers':[]}, slow, send)
        self.assertEqual(408, send.call_args_list[0].args[0]['status'])

    async def test_valid_chunks_reach_downstream_with_security_headers(self):
        original=[{'type':'http.request','body':b'{','more_body':True},{'type':'http.request','body':b'}','more_body':False}]
        observed=[]
        async def downstream(scope,receive,send):
            observed.extend([await receive(),await receive()])
            await send({'type':'http.response.start','status':200,'headers':[]})
            await send({'type':'http.response.body','body':b'ok'})
        send=AsyncMock()
        await BodyLimitMiddleware(downstream)({'type':'http','path':'/x','headers':[]},AsyncMock(side_effect=original),send)
        self.assertEqual(original,observed)
        self.assertIn((b'cache-control',b'no-store'),send.call_args_list[0].args[0]['headers'])

    async def test_downstream_failure_is_not_retried(self):
        downstream = AsyncMock(side_effect=RuntimeError('failure'))
        send = AsyncMock()
        with self.assertRaises(RuntimeError):
            await BodyLimitMiddleware(downstream)({'type':'http','path':'/x','headers':[]}, AsyncMock(return_value={'type':'http.request','body':b'{}'}), send)
        send.assert_not_awaited()


class PublicBoundaryTests(unittest.TestCase):
    def request(self, peer, headers=()):
        return Request({'type':'http','client':(peer,123),'headers':[(k.encode(),v.encode()) for k,v in headers]})

    def test_proxy_headers_require_trusted_peer_and_walk_right(self):
        request=self.request('192.0.2.1',[('x-forwarded-for','1.2.3.4, 203.0.113.8')])
        with patch.dict(os.environ, {'JWXT_TRUSTED_PROXY_CIDRS':'127.0.0.0/8'}, clear=True):
            self.assertEqual('192.0.2.1',jwxt._client_identity(request))
            request=self.request('127.0.0.1',[('x-forwarded-for','1.2.3.4, 203.0.113.8, 127.0.0.2')])
            self.assertEqual('203.0.113.8',jwxt._client_identity(request))
            self.assertEqual('127.0.0.1',jwxt._client_identity(self.request('127.0.0.1',[('x-forwarded-for','bad')])) )

    def test_cloudflare_header_needs_explicit_ingress_option(self):
        req=self.request('127.0.0.1',[('cf-connecting-ip','203.0.113.9')])
        with patch.dict(os.environ, {'JWXT_TRUSTED_PROXY_CIDRS':'127.0.0.1/32','JWXT_TRUST_CF_CONNECTING_IP':'true'},clear=True):
            self.assertEqual('203.0.113.9',jwxt._client_identity(req))

    def test_environment_whitelist_and_bounded_limiter(self):
        with patch.dict(os.environ, {'PATH':'runtime','CALENDAR_ADMIN_TOKEN':'secret','ADMIN_TOKEN':'secret','PRIVATE_DB_PATH':'secret'},clear=True):
            self.assertEqual({'PATH':'runtime'},jwxt._query_process_environment())
        limiter=jwxt.SlidingWindowRateLimiter(1,60)
        limiter.max_identities=2
        self.assertTrue(limiter.allow('a',0));self.assertTrue(limiter.allow('b',0))
        self.assertFalse(limiter.allow('c',0))
        self.assertEqual(2,len(limiter._events))

    def test_same_account_term_does_not_spawn_twice(self):
        payload=jwxt.PipelineRequest(username='parallel-test',encrypted_password='secret',year_term='2026-2027-1')
        entered,release=threading.Event(),threading.Event()
        errors=[]
        def pipeline(**kwargs):
            self.assertTrue(kwargs['headless']);self.assertEqual('prod',kwargs['env_name'])
            entered.set();release.wait(2);return {}
        def invoke():
            try: jwxt.fetch_term_schedule_notices(payload,self.request('192.0.2.88'))
            except Exception as exc: errors.append(exc)
        with patch.object(jwxt,'run_pipeline_isolated',side_effect=pipeline) as run:
            worker=threading.Thread(target=invoke);worker.start()
            try:
                self.assertTrue(entered.wait(1))
                with self.assertRaises(ServiceError) as error: jwxt.fetch_term_schedule_notices(payload,self.request('192.0.2.89'))
                self.assertEqual('query_in_progress',error.exception.code)
            finally: release.set();worker.join()
            self.assertEqual(1,run.call_count)
            self.assertEqual([],errors)

    def test_value_error_never_returns_upstream_text(self):
        result=Mock()
        with patch.dict(os.environ),patch.object(jwxt.os,'setsid',create=True),patch.object(jwxt,'run_pipeline',side_effect=ValueError('private-url-password')):
            jwxt._pipeline_process_entry(result,{})
        self.assertNotIn('private',str(result.put.call_args))

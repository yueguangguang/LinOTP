# -*- coding: utf-8 -*-
#
#    LinOTP - the open source solution for two factor authentication
#    Copyright (C) 2010 - 2016 LSE Leading Security Experts GmbH
#
#    This file is part of LinOTP server.
#
#    This program is free software: you can redistribute it and/or
#    modify it under the terms of the GNU Affero General Public
#    License, version 3, as published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the
#               GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
#    E-mail: linotp@lsexperts.de
#    Contact: www.linotp.org
#    Support: www.lsexperts.de
#


"""
reporitng controller - interfaces for Reporting
"""
import logging

from datetime import datetime

from pylons import request, response, config, tmpl_context as c
from linotp.lib.base import BaseController
from linotp.lib.context import request_context

from linotp.lib.policy import (checkAuthorisation,
                               PolicyException,
                               getAdminPolicies)

from linotp.lib.realm import match_realms

from linotp.lib.reply import (sendResult,
                              sendError)
from linotp.lib.reporting import ReportingIterator
from linotp.lib.reporting import get_max
from linotp.lib.reporting import delete
from linotp.lib.user import (getUserFromRequest, )
from linotp.lib.util import check_session
from linotp.lib.util import get_client

from linotp.model.meta import Session

audit = config.get('audit')

log = logging.getLogger(__name__)


class ReportingController(BaseController):
    """
    reporting
    """

    def __before__(self, action, **params):
        """
        """
        try:
            log.debug('[__before__::%r] %r', action, params)

            c.audit = request_context['audit']
            c.audit['success'] = False

            c.audit['client'] = get_client(request)

            # Session handling
            check_session(request)

            request_context['Audit'] = audit
            checkAuthorisation(scope='reporting.access', method=action)

            return request

        except Exception as exception:
            log.exception(exception)
            Session.rollback()
            Session.close()
            return sendError(response, exception, context='before')

        finally:
            log.debug('[__before__::%r] done', action)

    def __after__(self, action):
        """
        """
        params = {}
        try:
            params.update(request.params)
            c.audit['administrator'] = getUserFromRequest(request).get('login')

            audit.log(c.audit)
            Session.commit()
            return request

        except Exception as exception:
            log.exception(exception)
            Session.rollback()
            return sendError(response, exception, context='after')

        finally:
            Session.close()
            log.debug('[__after__] done')

    def maximum(self):
        """
        method:
            reporting/maximum

        description:
            return the maximum of tokens in a given realm with given status

        arguments:
            * realms - required: takes realms, only the reporting entries for
                this realms will be displayed
            * status - optional: (default is 'active')
                takes assigned/unassigned/active/ etc.
                and shows max of lines in database with this characteristic

        returns:
            a json result with:
            { "head": [],
            "data": [ [row1], [row2] .. ]
            }

        exception:
            if an error occurs an exception is serialized and returned

        :return:
        """
        result = {}
        try:
            param = request.params
            request_realms = param.get('realms', '').split(',')
            status = param.get('status', ['total'])
            if status != ['total']:
                status = status.split(',')

            realm_whitelist = []
            policies = getAdminPolicies('maximum', scope='reporting.access')

            if policies['active'] and policies['realms']:
                realm_whitelist = policies.get('realms')

            # if there are no policies for us, we are allowed to see all realms
            if not realm_whitelist or '*' in realm_whitelist:
                realm_whitelist = request_context['Realms'].keys()

            realms = match_realms(request_realms, realm_whitelist)

            for realm in realms:
                for stat in status:
                    result[realm] = get_max(realm, stat)

            return sendResult(response, result)

        except PolicyException as policy_exception:
            log.exception(policy_exception)
            Session.rollback()
            return sendError(response, unicode(policy_exception), 1)

        except Exception as exc:
            log.exception(exc)
            Session.rollback()
            return sendError(response, exc)

        finally:
            Session.close()
            log.debug('[maximum] done')

    def delete_all(self):
        """
        method:
            reporting/delete_all

        description:
            delete entries from the reporting database table

        arguments:
        * realms - optional: takes realms, only the reporting entries
                from this realm are dedleted
        * status - optional: filters reporting entries by status
                like 'assigned' or 'inactive'

        returns: dict in which value is the number of deleted rows

        exception:
            if an error occurs an exception is serialized and returned
        """

        try:
            param = request.params
            request_realms = param.get('realms', '').split(',')
            status = param.get('status', ['total'])
            if status != ['total']:
                status = status.split(',')

            realm_whitelist = []
            policies = getAdminPolicies('delete_all', scope='reporting.access')

            if policies['active'] and policies['realms']:
                realm_whitelist = policies.get('realms')

            # if there are no policies for us, we are allowed to see all realms
            if not realm_whitelist or '*' in realm_whitelist:
                realm_whitelist = request_context['Realms'].keys()

            realms = match_realms(request_realms, realm_whitelist)

            if '*' in status:
                status.remove('*')
                status.extend(['active', 'inactive', 'assigned', 'unassigned',
                               'active&assigned', 'active&unassigned',
                               'inactive&assigned', 'inactive&unassigned',
                               'total'])

            result = delete(realms=realms, status=status)
            Session.commit()
            return sendResult(response, result)

        except PolicyException as policy_exception:
            log.exception(policy_exception)
            Session.rollback()
            return sendError(response, unicode(policy_exception), 1)

        except Exception as exc:
            log.exception(exc)
            Session.rollback()
            return sendError(response, exc)

        finally:
            Session.close()
            log.debug('[delete_all] done')

    def delete_before(self):
        """
        method:
            reporting/delete_before

        description:
            delete all entries from reporting database with respect to the
            arguments
            date must be given in format: 'yyyy-mm-dd'

        arguments:
        * date - optional: only delete entries which are older than date;
                date must be given in format 'yyyy-mm-dd'
                if no date is given, all entries get deleted
        * realms - optional: takes realms, only the reporting entries
                from this realm are dedleted
        * status - optional: filters reporting entries by status
                like 'assigned' or 'inactive'

        returns: dict in which value is the number of deleted rows

        exception:
            if an error occurs an exception is serialized and returned
        """

        try:

            param = request.params
            request_realms = param.get('realms', '').split(',')
            status = param.get('status', ['total'])
            if status != ['total']:
                status = status.split(',')

            param = request.params
            border_day = param.get('date')

            # this may throw ValueError if date is in wrong format
            datetime.strptime(border_day, "%Y-%m-%d")

            realm_whitelist = []
            policies = getAdminPolicies('delete_before', scope='reporting')

            if policies['active'] and policies['realms']:
                realm_whitelist = policies.get('realms')

            # if there are no policies for us, we are allowed to see all realms
            if not realm_whitelist or '*' in realm_whitelist:
                realm_whitelist = request_context['Realms'].keys()

            realms = match_realms(request_realms, realm_whitelist)

            result = delete(date=border_day, realms=realms, status=status)
            Session.commit()
            return sendResult(response, result)

        except PolicyException as policy_exception:
            log.exception(policy_exception)
            Session.rollback()
            return sendError(response, unicode(policy_exception), 1)

        except ValueError as value_error:
            log.exception(value_error)
            Session.rollback()
            return sendError(response, unicode(value_error), 1)

        except Exception as exc:
            log.exception(exc)
            Session.rollback()
            return sendError(response, exc)

        finally:
            Session.close()
            log.debug('[tokens] done')


    def show(self):
        """
        method:
            reporting/show

        description:
            show entries from the reporting database table

        arguments:
        * date - optional: only show entries which are newer than date;
                date must be given in format 'yyyy-mm-dd'
                if no date is given, all entries are shown
        * realms - optional: takes realms, only the reporting entries
                from this realm are shown
        * status - optional: filters reporting entries by status
                like 'assigned' or 'inactive'

        returns: a json result with:
            { "head": [],
            "data": [ [row1], [row2] .. ]
            }


        exception:
            if an error occurs an exception is serialized and returned
        """

        try:
            param = request.params
            request_realms = param.get('realms', '').split(',')
            status = param.get('status', [])

            param = request.params
            border_day = param.get('date')

            if border_day:
                # this may throw ValueError if date is in wrong format
                datetime.strptime(border_day, "%Y-%m-%d")

            realm_whitelist = []
            policies = getAdminPolicies('show', scope='reporting.access')

            if policies['active'] and policies['realms']:
                realm_whitelist = policies.get('realms')

            # if there are no policies for us, we are allowed to see all realms
            if not realm_whitelist or '*' in realm_whitelist:
                realm_whitelist = request_context['Realms'].keys()

            realms = match_realms(request_realms, realm_whitelist)

            reports = ReportingIterator(realms=realms, status=status, date=None,
                                        page=None, psize=None, sort=None,
                                        sortdir=None)

            c.audit['success'] = True

            # put in the result
            result = {}

            # now row by row
            lines = []
            for rep in reports:
                # CKO:
                log.debug("tokenline: %s" % rep)
                lines.append(rep)

            result["data"] = lines
            result["resultset"] = reports.getResultSetInfo()

            Session.commit()
            return sendResult(response, result)

        except PolicyException as policy_exception:
            log.exception(policy_exception)
            Session.rollback()
            return sendError(response, unicode(policy_exception), 1)

        except ValueError as value_error:
            log.exception(value_error)
            Session.rollback()
            return sendError(response, unicode(value_error), 1)

        except Exception as exc:
            log.exception(exc)
            Session.rollback()
            return sendError(response, exc)

        finally:
            Session.close()
            log.debug('[delete_before] done')

//
//  WMUser.m
//  EHModel
//

#import "WMUser.h"
@implementation WMUser
EH_MODEL_IMPLEMENTION_JSON_KEYS(
    EH_PAIR(login, login),
    EH_PAIR(userID, user_id),
    EH_PAIR(avatarURL, meta.avatar_url),
    EH_PAIR(gravatarID, gravatar_id),
    EH_PAIR(htmlURL, html_url),
    EH_PAIR(followersURL, followers_url),
    EH_PAIR(followingURL, following_url),
    EH_PAIR(gistsURL, gists_url),
    EH_PAIR(starredURL, starred_url),
    EH_PAIR(subscriptionsURL, subscriptions_url),
    EH_PAIR(organizationsURL, organizations_url),
    EH_PAIR(reposURL, repos_url),
    EH_PAIR(eventsURL, events_url),
    EH_PAIR(receivedEventsURL, receivedEvents_url),
    EH_PAIR(siteAdmin, site_admin),
    EH_PAIR(publicRepos, public_repos),
    EH_PAIR(publicGists, public_gists),
    EH_PAIR(createdAt, created_at),
    EH_PAIR(updatedAt, updated_at),
    EH_PAIR(type, type),
    EH_PAIR(name, name),
    EH_PAIR(company, company),
    EH_PAIR(blog, blog),
    EH_PAIR(location, location),
    EH_PAIR(email, email),
    EH_PAIR(hireable, hireable),
    EH_PAIR(bio, bio),
    EH_PAIR(followers, followers),
    EH_PAIR(following, following)

        )
EH_MODEL_IMPLEMENTION_UNIQUE(userID)
EH_MODEL_IMPLEMENTION_DB_KEYS(login, userID, avatarURL, gravatarID, htmlURL, followersURL, followingURL, gistsURL, starredURL, subscriptionsURL, organizationsURL, reposURL, eventsURL, receivedEventsURL, siteAdmin, publicRepos, publicGists, createdAt, updatedAt, type, name, company, blog, location, email, hireable, bio, followers, following)


@end

/* healthd 不在这套系统里。BatteryService 拿到空的 batterypropreg 就空指针，
 * 整段核心服务跟着停。这里只把注册调用吃掉。
 */
#include <binder/IPCThreadState.h>
#include <binder/IServiceManager.h>
#include <binder/ProcessState.h>

using namespace android;

class BatReg : public BBinder {
public:
	status_t onTransact(uint32_t code, const Parcel &data, Parcel *reply, uint32_t flags)
	{
		if (code == IBinder::FIRST_CALL_TRANSACTION ||
		    code == IBinder::FIRST_CALL_TRANSACTION + 1)
			return OK;
		return BBinder::onTransact(code, data, reply, flags);
	}
};

int main(void)
{
	sp<IServiceManager> sm = defaultServiceManager();
	if (sm == 0)
		return 1;
	sm->addService(String16("batterypropreg"), new BatReg());
	ProcessState::self()->startThreadPool();
	IPCThreadState::self()->joinThreadPool();
	return 0;
}

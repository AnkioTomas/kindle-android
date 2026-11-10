package com.kindle.home;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.os.FileObserver;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public class Home extends Activity {
    private static final String KFB = "/dev/kfb";

    private TextView status;
    private LinearLayout apps;
    private ScrollView appScroll;
    private LinearLayout settingsBox;
    private EditText settings;
    private boolean editing;
    private String lastApp = "";
    private FileObserver ctl;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = column();
        status = new TextView(this);
        status.setTextSize(18);
        status.setPadding(24, 24, 24, 8);
        root.addView(status);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(button("退出", "exit"));
        row.addView(button("停止", "stop"));
        row.addView(button("重启", "restart"));
        row.addView(settingsButton());
        root.addView(row);

        apps = column();
        appScroll = new ScrollView(this);
        appScroll.addView(apps);
        root.addView(appScroll, fill());

        settings = new EditText(this);
        settings.setTextSize(16);
        settings.setGravity(Gravity.TOP);
        settingsBox = column();
        settingsBox.addView(settings, fill());
        Button save = new Button(this);
        save.setText("保存");
        save.setTextSize(18);
        save.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                saveSettings();
            }
        });
        settingsBox.addView(save);
        settingsBox.setVisibility(View.GONE);
        root.addView(settingsBox, fill());
        setContentView(root);

        ctl = new FileObserver(KFB + "/ctl",
                FileObserver.MOVED_TO | FileObserver.CLOSE_WRITE | FileObserver.CREATE) {
            @Override
            public void onEvent(int event, String path) {
                if ("app".equals(path))
                    openRequested();
                else if ("status".equals(path))
                    showStatus();
            }
        };
        ctl.startWatching();
    }

    @Override
    protected void onResume() {
        super.onResume();
        touch(KFB + "/ctl/shown");
        requestStatus();
        if (!editing)
            fillApps();
        openRequested();
    }

    @Override
    protected void onDestroy() {
        ctl.stopWatching();
        super.onDestroy();
    }

    private void openRequested() {
        final String s = readFile(KFB + "/ctl/app");
        if (s.length() == 0 || s.equals(lastApp))
            return;
        lastApp = s;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                launch(s);
            }
        });
    }

    private void launch(String s) {
        try {
            if ("home".equals(s)) {
                Intent home = new Intent(this, Home.class);
                home.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_SINGLE_TOP
                        | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                startActivity(home);
                return;
            }
            int slash = s.indexOf('/');
            Intent intent;
            if (slash > 0) {
                intent = new Intent(Intent.ACTION_MAIN);
                intent.setClassName(s.substring(0, slash), s.substring(slash + 1));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            } else {
                intent = getPackageManager().getLaunchIntentForPackage(s);
            }
            if (intent != null)
                startActivity(intent);
        } catch (ActivityNotFoundException e) {
            lastApp = "";
        } catch (SecurityException e) {
            lastApp = "";
        }
    }

    private void fillApps() {
        apps.removeAllViews();
        Intent query = new Intent(Intent.ACTION_MAIN);
        query.addCategory(Intent.CATEGORY_LAUNCHER);
        final PackageManager pm = getPackageManager();
        List<ResolveInfo> list = pm.queryIntentActivities(query, 0);
        Collections.sort(list, new Comparator<ResolveInfo>() {
            @Override
            public int compare(ResolveInfo a, ResolveInfo b) {
                return a.loadLabel(pm).toString().compareToIgnoreCase(b.loadLabel(pm).toString());
            }
        });
        for (int i = 0; i < list.size(); i++) {
            final ResolveInfo info = list.get(i);
            if ("com.kindle.home".equals(info.activityInfo.packageName))
                continue;
            Button b = new Button(this);
            b.setText(info.loadLabel(pm));
            b.setTextSize(20);
            b.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Intent intent = new Intent(Intent.ACTION_MAIN);
                    intent.addCategory(Intent.CATEGORY_LAUNCHER);
                    intent.setClassName(info.activityInfo.packageName, info.activityInfo.name);
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(intent);
                }
            });
            apps.addView(b);
        }
    }

    private void showStatus() {
        final String text = statusLine(readFile(KFB + "/ctl/status"));
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                status.setText(text);
            }
        });
    }

    private static String statusLine(String raw) {
        String time = value(raw, "time");
        String batt = value(raw, "batt");
        String wifi = value(raw, "wifi");
        String fl = value(raw, "fl");
        StringBuilder s = new StringBuilder();
        if (time.length() > 0)
            s.append(time).append("  ");
        if (batt.length() > 0)
            s.append(batt).append("%  ");
        if ("1".equals(wifi))
            s.append("无线  ");
        if (fl.length() > 0)
            s.append("亮度 ").append(fl);
        return s.toString();
    }

    private static String value(String raw, String key) {
        String prefix = key + "=";
        int from = 0;
        while (from < raw.length()) {
            int nl = raw.indexOf('\n', from);
            if (nl < 0)
                nl = raw.length();
            String line = raw.substring(from, nl);
            if (line.startsWith(prefix))
                return line.substring(prefix.length());
            from = nl + 1;
        }
        return "";
    }

    private void saveSettings() {
        String text = settings.getText().toString();
        if (!text.endsWith("\n"))
            text = text + "\n";
        File tmp = new File(KFB + "/ctl/settings.new.tmp");
        File dest = new File(KFB + "/ctl/settings.new");
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(tmp);
            out.write(text.getBytes("UTF-8"));
            out.close();
            out = null;
            if (!tmp.renameTo(dest))
                return;
            editing = false;
            settingsBox.setVisibility(View.GONE);
            appScroll.setVisibility(View.VISIBLE);
            fillApps();
        } catch (IOException ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private void requestStatus() {
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(KFB + "/kfb.fifo");
            out.write("cmd:status\n".getBytes("UTF-8"));
        } catch (IOException ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private Button settingsButton() {
        Button b = new Button(this);
        b.setText("设置");
        b.setTextSize(18);
        b.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                editing = !editing;
                if (editing) {
                    settings.setText(readFile(KFB + "/settings"));
                    appScroll.setVisibility(View.GONE);
                    settingsBox.setVisibility(View.VISIBLE);
                } else {
                    settingsBox.setVisibility(View.GONE);
                    appScroll.setVisibility(View.VISIBLE);
                }
            }
        });
        return b;
    }

    private Button button(final String label, final String name) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextSize(18);
        b.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                touch(KFB + "/ctl/" + name);
            }
        });
        return b;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private static LinearLayout.LayoutParams fill() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT, 1);
    }

    private static void touch(String path) {
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(path);
        } catch (IOException ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static String readFile(String path) {
        FileInputStream in = null;
        try {
            in = new FileInputStream(path);
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            byte[] tmp = new byte[1024];
            int n;
            while ((n = in.read(tmp)) > 0)
                buf.write(tmp, 0, n);
            return buf.toString("UTF-8").trim();
        } catch (IOException ignored) {
            return "";
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (IOException ignored) {
                }
            }
        }
    }
}

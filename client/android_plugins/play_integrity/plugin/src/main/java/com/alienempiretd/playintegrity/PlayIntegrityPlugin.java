package com.alienempiretd.playintegrity;

import android.app.Activity;

import com.google.android.play.core.integrity.IntegrityManagerFactory;
import com.google.android.play.core.integrity.StandardIntegrityManager;
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest;
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider;
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Play Integrity standard requests for Godot (Android plugin v2).
 *
 * GDScript: Engine.get_singleton("PlayIntegrity"), then prepare(cloud_project_number)
 * once, then request_token(request_hash) per protected request. Results arrive as
 * signals. The server decodes and checks each token (from M4).
 *
 * API reference: https://developer.android.com/google/play/integrity/standard
 */
public class PlayIntegrityPlugin extends GodotPlugin {
    private StandardIntegrityTokenProvider tokenProvider;

    public PlayIntegrityPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "PlayIntegrity";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("prepared"));
        signals.add(new SignalInfo("prepare_failed", String.class));
        signals.add(new SignalInfo("token_ready", String.class));
        signals.add(new SignalInfo("token_failed", String.class));
        return signals;
    }

    /** Warms up a token provider. cloudProjectNumber is the linked Google Cloud project number, as digits. */
    @UsedByGodot
    public void prepare(String cloudProjectNumber) {
        Activity activity = getActivity();
        if (activity == null) {
            emitSignal("prepare_failed", "no activity yet");
            return;
        }
        long projectNumber;
        try {
            projectNumber = Long.parseLong(cloudProjectNumber.trim());
        } catch (NumberFormatException e) {
            emitSignal("prepare_failed", "the cloud project number must be digits only");
            return;
        }
        StandardIntegrityManager manager = IntegrityManagerFactory.createStandard(activity.getApplicationContext());
        manager.prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(projectNumber).build())
            .addOnSuccessListener(provider -> {
                tokenProvider = provider;
                emitSignal("prepared");
            })
            .addOnFailureListener(error -> emitSignal("prepare_failed", String.valueOf(error.getMessage())));
    }

    /** Requests a token bound to requestHash (at most 500 bytes; never raw sensitive data). */
    @UsedByGodot
    public void request_token(String requestHash) {
        if (tokenProvider == null) {
            emitSignal("token_failed", "call prepare first");
            return;
        }
        tokenProvider.request(StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build())
            .addOnSuccessListener(response -> emitSignal("token_ready", response.token()))
            .addOnFailureListener(error -> emitSignal("token_failed", String.valueOf(error.getMessage())));
    }
}
